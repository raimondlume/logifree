import Foundation

setvbuf(stdout, nil, _IOLBF, 0)

let args = Array(CommandLine.arguments.dropFirst())

switch args.first {
case nil, "run":
    Daemon().run()
case "hosts":
    HIDPP.softwareID = 0x0B // don't collide with a running daemon
    exit(Hosts.run(Array(args.dropFirst())))
default:
    print("""
        logifree                                    run the background agent (what launchd starts)
        \(Hosts.usage)
        """)
    exit(args.first == "help" || args.first == "--help" ? 0 : 2)
}
