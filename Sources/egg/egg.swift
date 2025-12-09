import EggCLI

@main
struct Egg {
    static func main() async throws {
        await EggCommand.main()
    }
}
