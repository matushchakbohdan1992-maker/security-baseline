import Foundation
func save(token: String, theme: String) {
    // ruleid: sb-secret-in-userdefaults
    UserDefaults.standard.set(token, forKey: "authToken")
    // ruleid: sb-secret-in-userdefaults
    UserDefaults.standard.set(token, forKey: "api_key")
    // ok: sb-secret-in-userdefaults
    UserDefaults.standard.set(theme, forKey: "appTheme")
}
