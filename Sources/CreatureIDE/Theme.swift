#if canImport(SwiftUI)
import SwiftUI

public enum Theme {
    // Custom colors matching the website palette
    public static let ink = Color(red: 10/255, green: 10/255, blue: 15/255)
    public static let paper = Color(red: 237/255, green: 233/255, blue: 216/255)
    public static let p2 = Color(red: 200/255, green: 196/255, blue: 178/255)
    public static let p3 = Color(red: 138/255, green: 135/255, blue: 120/255)
    public static let gold = Color(red: 255/255, green: 184/255, blue: 0/255)
    public static let teal = Color(red: 94/255, green: 234/255, blue: 212/255)
    public static let green = Color(red: 0/255, green: 255/255, blue: 136/255)
    public static let red = Color(red: 255/255, green: 95/255, blue: 86/255)
    
    public static let editorBackground = Color(red: 13/255, green: 13/255, blue: 20/255)
    public static let sidebarBackground = Color(red: 17/255, green: 17/255, blue: 24/255)
    
    // Font helpers using JetBrains Mono falling back to SF Mono
    public static func mono(_ size: CGFloat) -> Font {
        if NSFont(name: "JetBrains Mono", size: size) != nil {
            return Font.custom("JetBrains Mono", size: size)
        } else {
            return Font.system(size: size, design: .monospaced)
        }
    }
    
    public static func spaceGrotesk(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if NSFont(name: "Space Grotesk", size: size) != nil {
            return Font.custom("Space Grotesk", size: size).weight(weight)
        } else {
            return Font.system(size: size).weight(weight)
        }
    }
}

#endif
