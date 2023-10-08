module yu.filepath;

import std.file;
import std.path;

alias nowPath = getcwd;

pragma(inline)
@safe string exePath() {
    return thisExePath().dirName();
}

pragma(inline)
@safe string absoluteNowPath(string path){
    return absolutePath(path,nowPath());
}

pragma(inline)
@safe string absoluteExePath(string path){
    return absolutePath(path,exePath());
}



unittest
{
    import std.stdio;
    
    writeln("---------file path ------------\r\n");

    writeln(exePath());
    writeln(absoluteExePath("config.json"));

    writeln(nowPath());
    writeln(absoluteNowPath("config.json"));

    assert(absoluteNowPath("config.json") == absoluteExePath("config.json"));

    writeln("---------file path ------------\r\n");
}

