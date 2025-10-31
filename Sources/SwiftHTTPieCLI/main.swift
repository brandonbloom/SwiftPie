#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

import SwiftHTTPieCore

SwiftHTTPie.main(arguments: CommandLine.arguments)
