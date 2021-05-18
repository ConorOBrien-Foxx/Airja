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
    for(BigInt i = 0; i < b; i++) {
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

void callTopAsFunctionNTimes(Instance inst) {
    auto count = inst.popTop();
    BigInt* biRef = count.peek!BigInt;
    auto top = inst.popTop();
    Quote* qRef = top.peek!Quote;
    if(biRef !is null && qRef !is null) {
        for(int i = 0; i < *biRef; i++) {
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
    for(BigInt i = 0; i < e; i++) {
        Atom el = i;
        list ~= el;
    }
    return list;
}

Atom iotaUnary(Atom e) {
    return visitOverload!"iotaUnary"(e);
}

void quoteMapOnStack(alias withIndex = false)(Instance inst) {
    auto functor = inst.popTop();
    // Quote* qRef = functor.peek!Quote;
    auto arr = inst.popTop();
    Atom[]* src = arr.peek!(Atom[]);
    if(functor.isCallable && src !is null) {
        Atom[] res = (*src).dup;
        auto tempStack = inst.state.stack;
        foreach(i, ref e; res) {
            inst.state.stack = new Stack();
            static if(withIndex) {
                inst.push(BigInt(i));
            }
            inst.push(e);
            // inst.handleTokens(qRef.tokens);
            inst.call(functor);
            e = inst.popTop();
        }
        inst.state.stack = tempStack;
        inst.push(res);
    }
    else {
        inst.push(arr);
        inst.push(functor);
        throw new NoCaseException(arr, functor);
    }
}

void stackPop(Instance inst) {
    inst.popTop();
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
    //functions
    register("map", stackNilad!quoteMapOnStack);
    register("imap", stackNilad!(quoteMapOnStack!true));
    register("out", stackNilad!outputln);
    register("put", stackNilad!output);
    register("debug", stackNilad!debugStack);
    register("call", stackNilad!callTopAsFunction);
    register("ncall", stackNilad!callTopAsFunctionNTimes);
    register("bang", stackNilad!opbang);
    register("repr", stackUnaryFun!repr);
    register("stack", stackNilad!pushStackCopy);
    register("iota", stackUnaryFun!iotaUnary);
    //conversions
    register("to_s", stackUnaryFun!convertToString);
    // register("to_a", stackUnaryFun!convertToArray);
    // register("to_n", stackUnaryFun!convertToNumber);
    //misc info
    register("version", "0.0.1"d);
    register("nil", Nil);
}