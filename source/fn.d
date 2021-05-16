// generates functions
import std.variant;
import std.functional;
import std.stdio;
import std.bigint;
import std.traits : Parameters;
import std.algorithm : map;
import std.array : join;

import state : Atom, Nil, NilNoCase;
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
                mixin(text(
                    "res = t(",
                    params.length.iota.map!(
                        i => text("*variants[",i,"].peek!(params[",i,"])")
                    ).join(", "),
                    ");"
                ));
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
Atom addVisit(Atom a, Atom b) {
    return visitOverload!"add"(a, b);
}

BigInt sub(BigInt a, BigInt b) {
    return a - b;
}
Atom subVisit(Atom a, Atom b) {
    return visitOverload!"sub"(a, b);
}

Atom mulVisit(Atom a, Atom b) {
    return a * b;
}
Atom divVisit(Atom a, Atom b) {
    return a / b;
}
Atom factorial(Atom a) {
    Atom product = BigInt("1");
    for(Atom i = BigInt("2"); i <= a; i++) {
        product *= i;
    }
    return product;
}

import std.conv : to;
string reprCase(BigInt e) {
    return to!string(e);
}
string reprCase(string e) {
    return '"' ~ e ~ '"';
}
string reprCase(Atom[] arr) {
    return "[" ~ arr.map!repr.map!(to!string).join(", ") ~ "]";
}
Atom repr(Atom e) {
    return visitOverload!"reprCase"(e);
}

Atom pair(Atom a, Atom b) {
    Atom p = [ a, b ];
    return p;
}

void output(Instance inst) {
    Atom a = inst.state.stack.pop();
    writeln(a);
}

void debugStack(Instance inst) {
    writefln("Stack: %s", inst.state.stack.data);
}
void callTopAsFunction(Instance inst) {
    auto top = inst.popTop();
    Quote* qRef = top.peek!Quote;
    if(qRef !is null) {
        inst.handleTokens(qRef.tokens);
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

// helper / bootstrap
class NoCaseException : Exception {
    Atom[] args;
    this(string msg = "No such case", string file = __FILE__, size_t line = __LINE__) {
        super(msg, file, line);
    }
    this(Atoms...)(Atoms args) {
        this();
        // this.args = args;
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
    i.push(res);
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
        auto res = fn(aVal, bVal);
        if(res == NilNoCase) {
            i.push(aVal);
            i.push(bVal);
            throw new NoCaseException(aVal, bVal);
        }
        i.push(fn(aVal, bVal));
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
    register("add", stackBinaryFun!addVisit);
    register("sub", stackBinaryFun!subVisit);
    register("mul", stackBinaryFun!mulVisit);
    register("div", stackBinaryFun!divVisit);
    register("pair", stackBinaryFun!pair);
    //functions
    register("out", stackNilad!output);
    register("debug", stackNilad!debugStack);
    register("call", stackNilad!callTopAsFunction);
    register("opbang", stackNilad!opbang);
    register("repr", stackUnaryFun!repr);
    //misc info
    register("version", "1.0");
    register("nil", Nil);
}