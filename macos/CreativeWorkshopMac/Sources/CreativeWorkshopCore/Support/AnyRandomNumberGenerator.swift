/// Type-erased `RandomNumberGenerator` so a random source can be injected (e.g. via an
/// `init` parameter defaulting to `SystemRandomNumberGenerator`) and swapped for a
/// seeded generator in tests without exposing an existential to `inout` generic APIs.
package struct AnyRandomNumberGenerator: RandomNumberGenerator {
    private var base: RandomNumberGenerator

    package init(_ base: RandomNumberGenerator) {
        self.base = base
    }

    package mutating func next() -> UInt64 {
        base.next()
    }
}
