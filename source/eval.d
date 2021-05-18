import std.stdio;
import std.variant;
import std.conv : to;
import std.bigint;
// import std.functional;

import tokenize;
import state;
import fn;
import quote;

//TODO: bigfloat
Atom parseNumber(string repr) {
    // TODO: other types
    Atom v = BigInt(repr);
    // Variant v = to!int(repr);
    return v;
}

Atom parseString(string repr) {
    import std.array : replace;
    Atom v = repr[1..$-1].replace("\"\"", "\"");
    return v;
}

alias StackCallable = void delegate(eval.Instance);

Atom[string] inheritedMemory;
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
    
    State state() {
        return states[$-1];
    }
    void openScope() {
        states ~= new State();
    }
    void closeScope() {
        states[$ - 2].stack = state.stack;
        states.length--;
    }
    void setLocalVar(string name, Atom val) {
        state.setVar(name, val);
    }
    void setGlobalVar(string name, Atom val) {
        states[0].setVar(name, val);
    }
    auto getVar(string name) {
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
        Atom[] args;
        string[] arg_names;
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
        handleTokens(q.tokens);
        closeScope();
    }
    
    void handleInstruction(Token tok) {
        if(quoteDepth > 0 && !tok.isQuoteDelimiter) {
            if(tok.type == TokenType.QUOTE_SEP && !hasQuoteSep) {
                quoteSepIndex = buildQuote.length;
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
                quoteDepth++;
                break;
                
            case TokenType.QUOTE_END:
                quoteDepth--;
                if(quoteDepth == 0) {
                    state.stack.push(new Quote(
                        buildQuote[0..quoteSepIndex],
                        buildQuote[quoteSepIndex..$]
                    ));
                }
                break;
            
            case TokenType.WORD:
                try {
                    auto val = getVar(tok.raw);
                    if(val.convertsTo!StackCallable) {
                        call(tok, *val.peek!StackCallable);
                    }
                    else if(val.convertsTo!Quote) {
                        call(*val.peek!Quote);
                    }
                    else {
                        state.stack.push(val);
                    }
                } catch(MissingKeyException e) {
                    writefln("[%u:%u] Undefined variable '%s'", tok.row, tok.col, tok.raw);
                }
                break;
            
            case TokenType.OP:
                string name = tok.payload;
                auto res = getVar(name);
                call(tok, *res.peek!StackCallable);
                break;
            
            case TokenType.SET_LOCAL:
                setLocalVar(tok.payload, popTop());
                break;
            
            case TokenType.SET_FUNCTION:
                setGlobalVar(tok.payload, popTop());
                break;
            
            case TokenType.WHITESPACE, TokenType.QUOTE_SEP:
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
    instance.run;
    // writeln(instance.state.stack.data);
}