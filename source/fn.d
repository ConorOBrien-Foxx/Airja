// generates functions
import std.variant;
import std.functional;
import std.stdio;
import std.bigint;
import std.traits : Parameters, ReturnType;
import std.algorithm : map;
import std.array : join;
import std.meta : Alias;

import state : Atom, Nil, NilNoCase, NilNoReturn, NilClass;
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
            foreach(i, p; params) {
                auto v = variants[i].peek!p;
                if(v is null) {
                    valid = false;
                    break;
                }
            }
            if(valid) {
                // writeln(typeid(t));
                // writeln(ReturnType!t);
                mixin(text(
                    isVoid ? "": "res = ",
                    "t(",
                    params.length.iota.map!(
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

BigInt add(BigInt a, BigInt b) {
    return a + b;
}
string add(string a, string b) {
    return a ~ b;
}
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
string mul(string a, BigInt b) {
    import std.range : repeat;
    string res;
    for(BigInt i = 0; i < b; i++) {
        res ~= a;
    }
    return res;
}
string mul(BigInt b, string a) {
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

Atom div(Atom a, Atom b) {
    return a / b;
}

import std.conv : to;
string repr(BigInt e) {
    return to!string(e);
}
string repr(string e) {
    return '"' ~ e ~ '"';
}
string repr(Atom[] arr) {
    return "(" ~ arr.map!repr.map!(to!string).join(" ") ~ ")";
}
string repr(NilClass nil) {
    return nil.toString();
}
string repr(Quote q) {
    return "[" ~ q.tokens.map!"a.raw".join ~ "]";
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
        inst.handleTokens(qRef.tokens);
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
            inst.handleTokens(qRef.tokens);
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

string convertToString(string e) { return e; }
string convertToString(BigInt e) { return to!string(e); }
string convertToString(Atom[] e) { return e.map!(p => to!string(convertToString(p))).join(""); }
string convertToString(Quote e) { return e.tokens.map!"a.raw".join(""); }
Atom convertToString(Atom e) {
    return visitOverload!"convertToString"(e);
}
// Atom convertToArray(Atom e) {
    // return visitOverload!convertToArray(e);
// }
// Atom convertToNumber(Atom e) {
    // return visitOverload!convertToNumber(e);
// }

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
    void register(Fn)(string key, Fn fn) {
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
    //functions
    register("out", stackNilad!outputln);
    register("put", stackNilad!output);
    register("debug", stackNilad!debugStack);
    register("call", stackNilad!callTopAsFunction);
    register("ncall", stackNilad!callTopAsFunctionNTimes);
    register("opbang", stackNilad!opbang);
    register("repr", stackUnaryFun!repr);
    register("stack", stackNilad!pushStackCopy);
    //conversions
    register("to_s", stackUnaryFun!convertToString);
    // register("to_a", stackUnaryFun!convertToArray);
    // register("to_n", stackUnaryFun!convertToNumber);
    //misc info
    register("version", "1.0");
    register("nil", Nil);
}