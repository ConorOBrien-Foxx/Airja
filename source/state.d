import std.variant;
import std.bigint;

import quote : Quote;
import eval : StackCallable;

class StackEmptyException : Exception {
    this(string msg = "Popping from an empty stack", string file = __FILE__, size_t line = __LINE__) {
        super(msg, file, line);
    }
}

class NilClass {
    static nextId = 0;
    uint uuid;
    
    this() {
        this.uuid = nextId;
        nextId++;
    }
    
    override string toString() {
        import std.conv : text;
        return uuid ? text("nil#", uuid) : "nil";
    }
}

static NilClass Nil;
static NilClass NilNoCase;
static NilClass NilNoReturn;
static this() {
    Nil = new NilClass();
    NilNoCase = new NilClass();
    NilNoReturn = new NilClass();
}

alias Atom = Algebraic!(string, BigInt, Quote, StackCallable, This[], NilClass);

class Stack {
    Atom[] data;
    
    void push(Atom e) {
        data ~= e;
    }
    
    Stack dup() {
        Stack res = new Stack();
        res.data = data.dup;
        return res;
    }
    
    void clear() {
        data.length = 0;
    }
    
    // attempt cast
    //TODO: specify?
    void push(T)(T e)
    if(!is(Atom == T)) {
        Atom q = e;
        push(q);
    }
    
    Atom pop() {
        if(data.length == 0) {
            throw new StackEmptyException();
        }
        Atom val = data[$-1];
        data.length--;
        return val;
    }
    Atom peek() {
        if(data.length == 0) {
            throw new StackEmptyException("Peeking from an empty stack");
        }
        Atom val = data[$-1];
        return val;
    }
}

class MissingKeyException : Exception {
    this(string msg = "No such key", string file = __FILE__, size_t line = __LINE__) {
        super(msg, file, line);
    }
}

import std.stdio;
class State {
    Stack stack;
    Atom[string] vars;
    
    this() {
        stack = new Stack();
    }
    this(Atom[string] vars) {
        this();
        this.vars = vars;
    }
    this(State other) {
        this();
        // writeln("Setting stack");
        this.stack = other.stack.dup;
        // writeln("Setting vars");
        this.vars = other.vars.dup;//TODO: check if deep dup
        // writeln("closing");
    }
    
    void setVar(string s, Atom e) {
        vars[s] = e;
    }
    
    void setVar(T)(string s, T e)
    if(!is(Atom == T)) {
        Atom v = e;
        setVar(s, v);
    }
    Atom getVar(string s) {
        auto has = s in vars;
        if(has is null) {
            throw new MissingKeyException("No such key " ~ s);
        }
        return *has;
        // return vars[s];
    }
    bool hasVar(string s) {
        return !!(s in vars);
    }
}