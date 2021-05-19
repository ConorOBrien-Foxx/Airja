// generates functions
import std.variant;
import std.functional;
import std.stdio;
import std.bigint;
import std.traits : Parameters, ReturnType;
import std.algorithm : map;
import std.array : join;
import std.meta : Alias;

// import state : Stack, Atom, Nil, NilNoCase, NilNoReturn, NilClass;
import state;
import eval;
import quote;

static BI_ZERO = BigInt("0");
static BI_ONE = BigInt("1");

auto visitOverload(alias Fn, VariantType...)(VariantType variants) {
    import std.range : iota;
    import std.conv : text;
    static assert(VariantType.length > 0);
    
    alias VariantAtomType = VariantType[0];
    
    VariantAtomType res = NilNoCase;
    
    static foreach (t; __traits(getOverloads, mixin(__MODULE__), Fn)) {
        {
            alias isVoid = Alias!(is(ReturnType!t == void));
            alias params = Parameters!t;
            bool valid = true;
            bool atLeastOnceSpecific = false;
            // writeln(typeid(params));
            foreach(i, p; params) {
                auto v = variants[i].peek!p;
                if(v is null) {
                    /*if(is(VariantAtomType == p)) {
                        // pass
                    }
                    else {
                    */
                        valid = false;
                        break;
                    //}
                }
                else {
                    atLeastOnceSpecific = true;
                }
            }
            if(valid) {
                // writeln(typeid(t));
                // writeln(ReturnType!t);
                mixin(text(
                    isVoid ? "": "res = ",
                    "t(",
                    params.length.iota.map!(
                        // i => is(VariantAtomType == params[i])
                            // ? text("variants[",i,"]")
                            // :
                            
                        i => text("*variants[",i,"].peek!(params[",i,"])")
                    ).join(", "),
                    ");"
                ));
                static if(isVoid) {
                    res = NilNoReturn;
                }
                return res;
            }
        }
    }
   
    return res;
}

// Atom boolToAtom(bool b) {
    // Atom res = b ? BigInt("1") : BigInt("0");
    // return res;
// }

Atom isTruthy(BigInt i) {
    return Atom(i != 0);
}
Atom isTruthy(bool b) {
    return Atom(b);
}
Atom isTruthy(NilClass n) {
    return Atom(false);
}
Atom isTruthy(dstring d) {
    return Atom(d.length != 0);
}
Atom isTruthy(Atom[] arr) {
    return Atom(arr.length != 0);
}
Atom isTruthy(Atom a) {
    return visitOverload!"isTruthy"(a);
}
bool isTruthyToBool(Atom a) {
    if(!a.convertsTo!bool) {
        a = isTruthy(a);
    }
    return *a.peek!bool;
}

//TODO: expand
Atom equal(Atom a, Atom b) {
    Atom v = a == b;
    return v;
}
Atom notEqual(Atom a, Atom b) {
    Atom v = a != b;
    return v;
}


BigInt add(BigInt a, BigInt b) {
    return a + b;
}
dstring add(dstring a, dstring b) {
    return a ~ b;
}
// Quote add(Quote a, Quote b) {
    // return new Quote(a.tokens ~ b.tokens);
// }
Atom[] add(Atom[] a, Atom[] b) {
    return a ~ b;
}
// static foreach(type; ["BigInt", "dstring", "Quote", "Atom[]"]) {
    // mixin("Atom[] add(Atom[] a, " ~ type ~ " b) { return a ~ b; } ");
// }
// Atom[] add(Atom[] a, BigInt b) {
    // return a ~ b;
// }


Atom add(Atom a, Atom b) {
    return visitOverload!"add"(a, b);
}

BigInt sub(BigInt a, BigInt b) {
    return a - b;
}
Atom sub(Atom a, Atom b) {
    return visitOverload!"sub"(a, b);
}

BigInt mul(BigInt a, BigInt b) {
    return a * b;
}
dstring mul(dstring a, BigInt b) {
    import std.range : repeat;
    dstring res;
    // for(BigInt i = 0; i < b; i++) {
        // res ~= a;
    // }
    foreach(i; BI_ZERO..b) {
        res ~= a;
    }
    return res;
}
dstring mul(BigInt b, dstring a) {
    return mul(a, b);
}
Atom mul(Atom a, Atom b) {
    return visitOverload!"mul"(a, b);
}
BigInt factorial(BigInt a) {
    BigInt product = BigInt("1");
    for(BigInt i = BigInt("2"); i <= a; i++) {
        product = product.mul(i);
    }
    return product;
}
Atom factorial(Atom a) {
    return visitOverload!"factorial"(a);
}

BigInt div(BigInt a, BigInt b) {
    return a / b;
}
Atom div(Atom a, Atom b) {
    return visitOverload!"div"(a, b);
}

import std.conv : to;
dstring repr(BigInt e) {
    return to!dstring(e);
}
dstring repr(dstring e) {
    return '"' ~ e ~ '"';
}
dstring repr(Atom[] arr) {
    return "(" ~ arr.map!repr.map!(to!dstring).join(" ") ~ ")";
}
dstring repr(NilClass nil) {
    return to!dstring(nil.toString());
}
dstring repr(Quote q) {
    return "[" ~ q.tokens.map!"a.raw".join ~ "]";
}
dstring repr(TaggedStackCallable tsc) {
    return tsc.toString();
}
//TODO: expand booleans
dstring repr(bool b) {
    return b ? "1b" : "0b";
}

Atom repr(Atom e) {
    return visitOverload!"repr"(e);
}

Atom pair(Atom a, Atom b) {
    Atom p = [ a, b ];
    return p;
}

void output(Instance inst) {
    Atom a = inst.state.stack.pop();
    write(a);
}
void outputln(Instance inst) {
    output(inst);
    writeln();
}

void debugStack(Instance inst) {
    writefln("Stack: %s", repr(inst.state.stack.data));
}


void whileLoop(alias check = true)(Instance inst) {
    auto bodyFunction = inst.popTop();
    auto condition = inst.popTop();
    if(bodyFunction.isCallable && condition.isCallable) {
        while(true) {
            inst.call(condition);
            auto top = inst.popTop();
            if(isTruthyToBool(top) != check) break;
            inst.call(bodyFunction);
        }
    }
    else {
        inst.push(condition);
        inst.push(bodyFunction);
        throw new NoCaseException(condition, bodyFunction);
    }
}
void ifConditionSingle(alias check = true)(Instance inst) {
    auto bodyFunction = inst.popTop();
    auto condition = inst.popTop();
    if(bodyFunction.isCallable) {
        if(isTruthyToBool(condition) == check) {
            inst.call(bodyFunction);
        }
    }
    else {
        inst.push(condition);
        inst.push(bodyFunction);
        throw new NoCaseException(condition, bodyFunction);
    }
}
void ifElseCondition(Instance inst) {
    auto bodyFunction = inst.popTop();
    auto elseFunction = inst.popTop();
    auto condition = inst.popTop();
    if(bodyFunction.isCallable && elseFunction.isCallable) {
        if(isTruthyToBool(condition)) {
            inst.call(bodyFunction);
        }
        else {
            inst.call(elseFunction);
        }
    }
    else {
        inst.push(condition);
        inst.push(elseFunction);
        inst.push(bodyFunction);
        throw new NoCaseException(condition, elseFunction, bodyFunction);
    }

}

void callTopAsFunction(Instance inst) {
    auto top = inst.popTop();
    Quote* qRef = top.peek!Quote;
    if(qRef !is null) {
        inst.call(*qRef);
    }
    else {
        inst.push(top);
        throw new NoCaseException(top);
    }
}

void callTopAsFunctionOnArray(Instance inst) {
    auto bodyFunction = inst.popTop();
    // Quote* qRef = bodyFunction.peek!Quote;
    auto arr = inst.popTop();
    Atom[]* src = arr.peek!(Atom[]);
    if(bodyFunction.isCallable && src !is null) {
        Atom[] res = (*src).dup;
        auto tempStack = inst.state.stack;
        inst.state.stack = new Stack(res);
        inst.call(bodyFunction);
        Atom[] saveData = inst.state.stack.data;
        inst.state.stack = tempStack;
        inst.push(saveData);
    }
    else {
        inst.push(arr);
        inst.push(bodyFunction);
        throw new NoCaseException(arr, bodyFunction);
    }
}

void callTopAsFunctionNTimes(Instance inst) {
    auto count = inst.popTop();
    BigInt* biRef = count.peek!BigInt;
    auto top = inst.popTop();
    Quote* qRef = top.peek!Quote;
    if(biRef !is null && qRef !is null) {
        foreach(i; BI_ZERO..*biRef) {
            inst.call(*qRef);
        }
    }
    else {
        inst.push(top);
        inst.push(count);
        throw new NoCaseException(top, count);
    }
}
void opbang(Instance inst) {
    Quote* qRef = inst.peekTop().peek!Quote;
    if(qRef !is null) {
        callTopAsFunction(inst);
    }
    else {
        callUnary!factorial(inst);
    }
    
}
void duplicateTop(Instance inst) {
    auto top = inst.popTop();
    inst.push(top);
    inst.push(top);
}
void swapTopTwo(Instance inst) {
    auto aVal = inst.popTop();
    auto bVal = inst.popTop();
    inst.push(aVal);
    inst.push(bVal);
}

void pushStackCopy(Instance inst) {
    inst.push(inst.state.stack.data.dup);
}

Atom elementAccess(dstring str, BigInt index) {
    return Atom(to!dstring(str[cast(uint) index]));
}
Atom elementAccess(Atom[] arr, BigInt index) {
    return arr[cast(uint) index];
}
Atom elementAccess(Atom a, Atom b) {
    return visitOverload!"elementAccess"(a, b);
}

dstring convertToString(dstring e) { return e; }
dstring convertToString(BigInt e) { return to!dstring(e); }
dstring convertToString(Atom[] e) { return e.map!(p => to!dstring(convertToString(p))).join(""); }
dstring convertToString(Quote e) { return e.tokens.map!"a.raw".join(""); }
Atom convertToString(Atom e) {
    return visitOverload!"convertToString"(e);
}
// Atom convertToArray(Atom e) {
    // return visitOverload!convertToArray(e);
// }
// Atom convertToNumber(Atom e) {
    // return visitOverload!convertToNumber(e);
// }

Atom[] iotaUnary(BigInt e) {
    Atom[] list;
    // for(BigInt i = 0; i < e; i++) {
    foreach(i; BI_ZERO..e) {
        Atom el = i;
        list ~= el;
    }
    return list;
}

Atom iotaUnary(Atom e) {
    return visitOverload!"iotaUnary"(e);
}

BigInt sizeOfTop(Atom[] arr) {
    BigInt k = arr.length;
    return k;
}
Atom sizeOfTop(Atom e) {
    return visitOverload!"sizeOfTop"(e);
}

void quoteMapOnStack(alias withIndex = false)(Instance inst) {
    auto bodyFunction = inst.popTop();
    // Quote* qRef = bodyFunction.peek!Quote;
    auto arr = inst.popTop();
    Atom[]* src = arr.peek!(Atom[]);
    if(bodyFunction.isCallable && src !is null) {
        Atom[] res = (*src).dup;
        auto tempStack = inst.state.stack;
        foreach(i, ref e; res) {
            inst.state.stack = new Stack();
            static if(withIndex) {
                inst.push(BigInt(i));
            }
            inst.push(e);
            // inst.handleTokens(qRef.tokens);
            inst.call(bodyFunction);
            e = inst.popTop();
        }
        inst.state.stack = tempStack;
        inst.push(res);
    }
    else {
        inst.push(arr);
        inst.push(bodyFunction);
        throw new NoCaseException(arr, bodyFunction);
    }
}

void stackPop(Instance inst) {
    inst.popTop();
}

void gather(Instance inst) {
    import std.array : insertInPlace;
    auto n = inst.popTop();
    BigInt* nVal = n.peek!BigInt;
    if(nVal !is null) {
        Atom[] res;
        foreach(i; BI_ZERO..*nVal) {
            // res ~= inst.popTop();
            res.insertInPlace(0, inst.popTop());
        }
        Atom toPush = res;
        inst.push(toPush);
    }
    else {
        inst.push(n);
        throw new NoCaseException(n);
    }
}

// helper / bootstrap
class NoCaseException : Exception {
    Atom[] args;
    this(string msg = "No such case", string file = __FILE__, size_t line = __LINE__) {
        super(msg, file, line);
    }
    this(Atoms...)(Atoms args) {
        this();
        foreach(arg; args) {
            this.args ~= arg;
        }
    }
}

auto callUnary(alias fn)(Instance i) {
    auto top = i.popTop();
    auto res = fn(top);
    if(res == NilNoCase) {
        i.push(top);
        throw new NoCaseException(top);
    }
    if(res != NilNoReturn) {
        i.push(res);
    }
}
auto stackUnaryFun(alias pred = "a")() {
    alias fn = unaryFun!pred;
    return delegate(Instance i) {
        callUnary!fn(i);
    };
}
auto stackBinaryFun(alias pred = "b")() {
    alias fn = binaryFun!pred;
    return delegate(Instance i) {
        auto bVal = i.popTop();
        auto aVal = i.popTop();
        // writefln("Binary %s %s.", aVal, bVal);
        auto res = fn(aVal, bVal);
        if(res == NilNoCase) {
            // writefln("Binary %s %s.", aVal, bVal);
            i.push(aVal);
            i.push(bVal);
            throw new NoCaseException(aVal, bVal);
        }
        if(res != NilNoReturn) {
            i.push(res);
        }
    };
    // return toDelegate(fres);
}
auto stackNilad(alias nilad)() {
    return delegate(Instance i) {
        nilad(i);
    };
}

void initialize(Instance inst) {
    void register(Fn)(dstring key, Fn fn) {
        inst.state.setVar(key, fn);
    }
    //op aliases
    register("add", stackBinaryFun!add);
    register("sub", stackBinaryFun!sub);
    register("mul", stackBinaryFun!mul);
    register("div", stackBinaryFun!div);
    register("pair", stackBinaryFun!pair);
    register("dup", stackNilad!duplicateTop);
    register("swap", stackNilad!swapTopTwo);
    register("drop", stackNilad!stackPop);
    register("eq", stackBinaryFun!equal);
    register("neq", stackBinaryFun!notEqual);
    //control
    register("while", stackNilad!whileLoop);
    register("until", stackNilad!(whileLoop!false));
    register("when", stackNilad!ifConditionSingle);
    register("unless", stackNilad!(ifConditionSingle!false));
    register("if", stackNilad!ifElseCondition);
    //functions
    register("get", stackBinaryFun!elementAccess);
    register("map", stackNilad!quoteMapOnStack);
    register("imap", stackNilad!(quoteMapOnStack!true));
    register("out", stackNilad!outputln);
    register("put", stackNilad!output);
    register("debug", stackNilad!debugStack);
    register("call", stackNilad!callTopAsFunction);
    register("ncall", stackNilad!callTopAsFunctionNTimes);
    register("scall", stackNilad!callTopAsFunctionOnArray);
    register("bang", stackNilad!opbang);
    register("repr", stackUnaryFun!repr);
    register("stack", stackNilad!pushStackCopy);
    register("iota", stackUnaryFun!iotaUnary);
    register("gather", stackNilad!gather);
    register("size", stackUnaryFun!sizeOfTop);
    //conversions
    register("to_s", stackUnaryFun!convertToString);
    // register("to_a", stackUnaryFun!convertToArray);
    // register("to_n", stackUnaryFun!convertToNumber);
    //misc info
    register("version", "0.0.1"d);
    register("nil", Nil);
}