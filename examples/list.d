/+dub.sdl:
name "list"
dependency "volumeinfo" path="../"
+/

import std.stdio;
import std.format;
import volumeinfo;

string formatVolume(VolumeInfo volume)
{
    enum toMB = 1024*1024;
    return format("%s (%s, %s), %s MB free out of %s MB", volume.path, volume.type, volume.label, volume.bytesAvailable/toMB, volume.bytesTotal/toMB);
}

void main(string[] args)
{
    auto volumes = mountedVolumes();
    writeln("Mounted volumes: ");
    foreach(VolumeInfo volume; volumes) {
        writeln(formatVolume(volume));
    }

    if (args.length > 1) {
        writeln("Volumes for the passed paths: ");
        foreach(arg; args[1..$]) {
            try {
                writefln("%s resides on %s", arg, formatVolume(VolumeInfo(arg)));
            } catch(Exception e) {
                stderr.writefln("Error getting volume information: %s", e.msg);
            }
        }
    }
}
