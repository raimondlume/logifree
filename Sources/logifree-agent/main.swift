import Foundation
import LogifreeCore

setvbuf(stdout, nil, _IOLBF, 0)

let args = Array(CommandLine.arguments.dropFirst())

switch args.first {
case nil, "run":
    Daemon().run()
case "hosts":
    HIDPP.softwareID = 0x0B // don't collide with the running agent
    exit(HostsCommand.run(Array(args.dropFirst())))
default:
    print("""
        logifree                                    run the background agent (what launchd starts)
        \(HostsCommand.usage)

        Settings: ~/Library/Application Support/logifree/settings.json (or the Logifree app)
        """)
    exit(args.first == "help" || args.first == "--help" ? 0 : 2)
}
