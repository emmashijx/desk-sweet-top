import Foundation

func L(_ key: String, _ arguments: CVarArg...) -> String {
    let localized = Bundle.main.localizedString(forKey:key,value:key,table:nil)
    return arguments.isEmpty ? localized : String(format:localized,locale:Locale.current,arguments:arguments)
}
