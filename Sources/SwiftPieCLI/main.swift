#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

import SwiftPie

SwiftPie.main(arguments: CommandLine.arguments)
