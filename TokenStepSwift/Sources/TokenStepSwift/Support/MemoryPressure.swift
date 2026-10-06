import Darwin

enum MemoryPressure {
    static func relieveAllocatorPressure() {
        malloc_zone_pressure_relief(nil, 0)
    }
}
