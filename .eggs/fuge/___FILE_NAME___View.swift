// Available default macros:
//   - ___DATE___: Current date in default format
//   - ___DATE(yyyyMMdd)___: Current date in custom format
//   - ___SYSTEM_USER___: System username
//
// You can also define custom macros (e.g., ___USER_DEFINED___, ___FILE_NAME___) and provide values via:
//   - Command line: egg use <template-name> --user-defined foo --file-name bar
//   - Interactive prompt: will be asked during 'egg use' command

struct ___FILE_NAME___View: View {
    var body: some View {
        Text("___FILE_NAME___View")
    }
}