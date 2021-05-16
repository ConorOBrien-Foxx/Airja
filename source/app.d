import std.stdio;
import std.file;// : readText;
// import std.utf;

// import tokenize;
// import state;
import eval;

void main(string[] args) {
    string filename = args.length < 2 ? "test.airja" : args[1];
    string content = readText(filename);
    eval.execute(content);
    // Token[] tokens = tokenize.parse(content);
    // if(tokens == null) {
        // writeln("Unspecified error during parsing");
        // return;
    // }
    // foreach(i, token; tokens) {
        // if(token.type == TokenType.WHITESPACE) write("\x1b[30;1m");
        // writefln("%-4u %s", i, token);
        // write("\x1b[0m");
    // }
}
