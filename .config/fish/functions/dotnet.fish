function dotnet --description "Forward to Windows dotnet.exe on WSL, native dotnet elsewhere"
    if string match -qi '*microsoft*' < /proc/version
        dotnet.exe $argv
    else
        command dotnet $argv
    end
end
