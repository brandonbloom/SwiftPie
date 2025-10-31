#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

import SwiftHTTPie

SwiftHTTPie.main(arguments: CommandLine.arguments)
