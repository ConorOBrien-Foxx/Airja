import std.stdio;
import std.variant;
import std.conv : to;
import std.bigint;
// import std.functional;

import tokenize;
import state;
import fn;
import quote;

import std.file : thisExePath, exists;
import std.path : dirName, buildPath;
// import std.conv : to;

string BASE_PATH;

shared static this() {
    BASE_PATH = thisExePath.dirName;
}

//TODO: bigfloat
Atom parseNumber(dstring repr) {
    // TODO: other types
    if(repr[$ - 1] == 'b') {
        return Atom(!!BigInt(repr[0..$-1]));
    }
    else {
        return Atom(BigInt(repr));
    }
}

Atom parseString(dstring repr) {
    import std.array : replace;
    Atom v = repr[1..$-1].replace("\"\"", "\"");
    return v;
}

alias StackCallable = void delegate(eval.Instance);
struct TaggedStackCallable {
    Token token;
    dstring name;
    StackCallable stc;
    
    this(Token token, StackCallable stc) {
        this.token = token;
        this.name = token.payload;
        this.stc = stc;
    }
    
    dstring toString() {
        return "$" ~ this.name;
    }
}


bool isCallable(Atom e) {
    return e.convertsTo!StackCallable || e.convertsTo!TaggedStackCallable || e.convertsTo!Quote;
}

Atom[dstring] inheritedMemory;
class Instance {
    State[] states;
    Token[] tokens;
    
    Token[] buildQuote;
    ulong quoteSepIndex = 0;
    bool hasQuoteSep = false;
    uint quoteDepth = 0;
    
    this(Token[] tokens) {
        this.tokens = tokens;
        states ~= new State(inheritedMemory.dup);
    }
    
    bool[string] libsIncluded;
    void requireLibrary(string name) {
        if(name in libsIncluded && libsIncluded[name]) return;
        libsIncluded[name] = true;
        import std.file : readText;
        auto libName = buildPath(BASE_PATH, "lib", name);
        auto libNameTokens = libName ~ ".aout";
        Token[] tokens;
        if(libNameTokens.exists) {
            tokens = Token.fileToTokenArray(libNameTokens);
        }
        else {
            auto libNameRaw = libName ~ ".airja";
            if(!libNameRaw.exists) {
                writeln("No such library: <", name, ">");
                return;
            }
            tokens = libNameRaw.readText.parse;
        }
        handleTokens(tokens);
    }
    void requireLibrary(dstring name) {
        requireLibrary(name.to!string);
    }
    
    State state() {
        return states[$-1];
    }
    void openScope() {
        states ~= new State();
        state.stack = states[$ - 2].stack.dup;
    }
    void closeScope(bool append = false) {
        if(append) {
            states[$ - 2].stack ~= state.stack;
        }
        else {
            states[$ - 2].stack = state.stack;
        }
        states.length--;
    }
    void setLocalVar(dstring name, Atom val) {
        state.setVar(name, val);
    }
    void setGlobalVar(dstring name, Atom val) {
        states[0].setVar(name, val);
    }
    auto getVar(dstring name) {
        //TODO: maybe maintain a hash of identifiers?
        foreach_reverse(s; states) {
            if(s.hasVar(name)) {
                return s.getVar(name);
            }
        }
        return state.getVar(name);
    }
    
    void call(Token tok, StackCallable c) {
        import std.algorithm : map;
        import std.array : join;
        try {
            c(this);
        }
        catch(NoCaseException e) {
            writeln("No matching case for `" ~ tok.raw ~ "`");
            writeln("    Arguments: " ~ e.args.map!(a => repr(a).toString()).join(", "));
        }
    }
    
    void call(Quote q) {
        import std.array : insertInPlace;
        import std.range : lockstep;
        if(q.args.length) {
            Atom[] args;
            dstring[] arg_names;
            foreach(tok; q.args) {
                if(tok.type == TokenType.WORD) {
                    args.insertInPlace(0, popTop());
                    arg_names ~= tok.raw;
                }
            }
            openScope();
            foreach(name, value; lockstep(arg_names, args)) {
                setLocalVar(name, value);
            }
        }
        // writeln(q.tokens);
        handleTokens(q.tokens);
        
        if(q.args.length) {
            closeScope(q.hasQuoteSep);
        }
    }
    
    void call(TaggedStackCallable tsc) {
        call(tsc.token, tsc.stc);
    }
    
    bool call(Token tok, Atom val) {
        if(val.convertsTo!StackCallable) {
            call(tok, *val.peek!StackCallable);
        }
        else if(val.convertsTo!Quote) {
            call(*val.peek!Quote);
        }
        else if(val.convertsTo!TaggedStackCallable) {
            call(*val.peek!TaggedStackCallable);
        }
        else {
            return false;
        }
        return true;
    }
    
    bool call(Atom val) {
        return call(Token.none(), val);
    }
    
    void handleInstruction(Token tok) {
        if(quoteDepth > 0 && !tok.isQuoteDelimiter) {
            if(tok.type == TokenType.QUOTE_SEP && !hasQuoteSep) {
                quoteSepIndex = buildQuote.length;
                hasQuoteSep = true;
            }
            buildQuote ~= tok;
            return;
        }
        // writefln("Token: %s", tok);
        // writefln("Stack: %s", state.stack.data);
        switch(tok.type) {
            case TokenType.NUMBER:
                state.stack.push(parseNumber(tok.raw));
                break;
            
            case TokenType.STRING:
                state.stack.push(parseString(tok.raw));
                break;
            
            case TokenType.QUOTE_START:
                if(!quoteDepth) {
                    //init info
                    buildQuote = [];
                    hasQuoteSep = false;
                    quoteSepIndex = 0;
                }
                else {
                    buildQuote ~= tok;
                }
                quoteDepth++;
                break;
                
            case TokenType.QUOTE_END:
                quoteDepth--;
                if(quoteDepth == 0) {
                    state.stack.push(new Quote(
                        buildQuote[0..quoteSepIndex],
                        buildQuote[quoteSepIndex..$],
                        hasQuoteSep
                    ));
                }
                else {
                    buildQuote ~= tok;
                }
                break;
            
            case TokenType.ARRAY_START:
                openScope();
                state.stack.clear;
                break;
            
            case TokenType.ARRAY_END:
                //TODO: bound check
                foreach(k, v; state.vars) {
                    states[$ - 2].vars[k] = v;
                }
                auto temp = state.stack.data.dup;
                state.stack.clear;
                closeScope(true);
                push(temp);
                break;
            
            case TokenType.WORD:
                try {
                    auto val = getVar(tok.raw);
                    auto callSuccess = call(tok, val);
                    if(!callSuccess) {
                        state.stack.push(val);
                    }
                } catch(MissingKeyException e) {
                    writefln("[%u:%u] Undefined variable '%s'", tok.row, tok.col, tok.raw);
                }
                break;
            
            case TokenType.OP:
                dstring name = tok.payload;
                auto res = getVar(name);
                // call(tok, *res.peek!StackCallable);
                call(tok, res);
                break;
            
            case TokenType.SET_LOCAL:
                setLocalVar(tok.payload, popTop());
                break;
            
            case TokenType.SET_FUNCTION:
                setGlobalVar(tok.payload, popTop());
                break;
            
            case TokenType.VALUEOF:
                auto res = getVar(tok.payload);
                if(res.convertsTo!StackCallable) {
                    res = TaggedStackCallable(tok, *res.peek!StackCallable);
                }
                push(res);
                break;
            
            case TokenType.COMMENT:
                break;
            
            case TokenType.QUOTE_SEP:
                if(tok.payload) {
                    state.stack.clear;
                }
                break;
            
            case TokenType.WHITESPACE:
                //pass
                break;
            
            default:
                writefln("[%u:%u] Unhandled token type: %s", tok.row, tok.col, tok.type);
                break;
        }
    }
    
    void handleTokens(Token[] tokens) {
        foreach(token; tokens) {
            handleInstruction(token);
        }
    }
    
    void run() {
        handleTokens(tokens);
    }
    
    auto peekTop() {
        return state.stack.peek();
    }
    auto popTop() {
        return state.stack.pop();
    }
    void push(V)(V val) {
        state.stack.push(val);
    }
}

// default memory
shared static this() {
    auto dummy = new Instance([]);
    
    fn.initialize(dummy);
    
    inheritedMemory = dummy.state.vars;
}

void execute(string s) {
    Token[] tokens = tokenize.parse(s);
    auto instance = new Instance(tokens);
    instance.requireLibrary("std");
    instance.run;
    // writeln(instance.state.stack.data);
}