#if canImport(Darwin)
@preconcurrency import Darwin
#else
@preconcurrency import Glibc
#endif

import SwiftPie

SwiftPie.main(arguments: CommandLine.arguments)
