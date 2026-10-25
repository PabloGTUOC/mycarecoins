import Foundation

public enum L10n {
  private static func currentLanguageCode() -> String? {
    let defaults = UserDefaults(suiteName: CareCoinsShared.appGroup)
    return defaults?.string(forKey: CareCoinsShared.languageDefault)
  }

  private static func bundle(for languageCode: String?) -> Bundle {
    if let code = languageCode, !code.isEmpty,
       let path = Bundle.main.path(forResource: code, ofType: "lproj"),
       let bundle = Bundle(path: path) {
      return bundle
    }
    return Bundle.main
  }

  private static func locale(for languageCode: String?) -> Locale {
    if let code = languageCode, !code.isEmpty {
      return Locale(identifier: code)
    }
    return Locale.current
  }

  public static func t(_ key: String, _ args: CVarArg...) -> String {
    let code = currentLanguageCode()
    let b = bundle(for: code)
    let loc = locale(for: code)
    let format = b.localizedString(forKey: key, value: nil, table: nil)
    if args.isEmpty {
      return format
    }
    return String(format: format, locale: loc, arguments: args)
  }
}
