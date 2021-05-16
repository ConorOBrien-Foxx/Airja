import std.stdio;
import std.variant;
import std.conv : to;
import std.bigint;
// import std.functional;

import tokenize;
import state;
import fn;
import quote;

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
    State state;
    Token[] tokens;
    // uint index = 0;
    Token[] buildQuote;
    uint quoteDepth = 0;
    
    this(Token[] tokens) {
        this.tokens = tokens;
        state = new State(inheritedMemory.dup);
    }
    
    // bool isRunning() {
        // return index < tokens.length;
    // }
    
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
    
    void handleInstruction(Token tok) {
        if(quoteDepth > 0 && !tok.isQuoteDelimiter) {
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
                if(!quoteDepth) buildQuote = [];
                quoteDepth++;
                break;
                
            case TokenType.QUOTE_END:
                quoteDepth--;
                if(quoteDepth == 0) {
                    state.stack.push(new Quote(buildQuote));
                }
                break;
            
            case TokenType.WORD:
                if(state.hasVar(tok.raw)) {
                    auto val = state.getVar(tok.raw);
                    if(val.convertsTo!(StackCallable)) {
                        // val(this);
                        call(tok, *val.peek!StackCallable);
                    }
                    else {
                        state.stack.push(val);
                    }
                }
                else {
                    //TODO: error
                    writefln("No such token: %s", tok);
                }
                break;
            
            case TokenType.OP:
                string name = tok.payload;
                auto res = state.getVar(name);
                // writeln(res.type);
                // res(this);
                call(tok, *res.peek!StackCallable);
                break;
            
            case TokenType.WHITESPACE:
                //pass
                break;
            
            default:
                writefln("Unhandled token type: %s", tok.type);
                break;
        }
    }
    
    void handleTokens(Token[] tokens) {
        foreach(token; tokens) {
            handleInstruction(token);
        }
    }
    
    // void step() {
        // Token token = tokens[index];
        // handleInstruction(token);
        // index++;
    // }
    
    void run() {
        // while(isRunning) {
            // step();
        // }
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