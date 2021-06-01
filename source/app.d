import std.stdio;
import std.file;// : readText;
import std.getopt;
import std.path : stripExtension;

import tokenize;
import eval;

// import std.utf;

// import state;

void main(string[] args) {
    string filename;
    bool tokFile;
    
    auto info = getopt(args,
        std.getopt.config.bundling,
        "f|file", &filename,
        "t|tokenizeOut", &tokFile
    );
    
    if(filename == "" && args.length > 1) {
        filename = args[1];
    }
    
    if (info.helpWanted || filename == "") {
        defaultGetoptPrinter(
            "Some information about the program.",
            info.options
        );
        return;
    }
    
    string content = readText(filename);
    
    if(tokFile) {
        Token[] tokens = parse(content);
        if(tokens == null) {
            writeln("Unspecified error during parsing");
            return;
        }
        string outpath = stripExtension(filename) ~ ".aout";
        Token.writeTokenArrayToFile(tokens, outpath);
        return;
    }
    eval.execute(content);
}
