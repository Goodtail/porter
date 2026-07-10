import Foundation

/// Localized string lookup against the SPM module bundle.
///
/// Keys are the Korean source strings as written in code; translations live in
/// `Resources/<lang>.lproj/Localizable.strings` (ko is an identity table).
/// Interpolations map to format specifiers (Int → %lld, String → %@), so the
/// .strings keys must match those generated forms.
func L(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: .module)
}
