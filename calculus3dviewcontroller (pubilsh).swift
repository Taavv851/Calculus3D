//
//  Calculus3DViewController.swift
//  Calculus3D — Symbolic & 3D Visual Calculus Workbench for iOS
//
//  Copyright (c) 2026 Calculus3D Open Source Project. All rights reserved.
//  SPDX-License-Identifier: GPL-3.0-or-later AND CC-BY-NC-SA-4.0
//
//  【开源授权与反抄袭声明 / Open-Source Anti-Plagiarism Notice】：
//    1. 允许使用（Permitted Use）：本软件及源码免费开放给高校学生与教师用于微积分学习、复习与教学演示。
//    2. 严禁抄袭与去署名（No Plagiarism / Attribution Required）：
//       - 严禁删除、篡改本声明及内置的 `Calculus3DOriginalityWatermark` 防伪数字指纹；
//       - 严禁将本项目代码（全部或核心部分）抹去署名后直接冒充个人课程设计、毕业设计、学科竞赛作品或商业产品；
//       - 任何基于本项目的二次分发或修改版本必须保留原始项目署名并以相同开源协议开源。
//    3. 隐私安全承诺（Privacy Sanitized）：本源码及构建管线已全面执行隐私脱敏，零个人本机路径或真实姓名残留。
//

import UIKit
import SceneKit
import AudioToolbox
import ObjectiveC.runtime

// MARK: - 0A. 防抄袭数字水印与开源署名防篡改校验器 (Steganographic & FNV-1a Guard)

enum Calculus3DOriginalityWatermark {
    /// 官方开源授权与防抄袭署名（受 FNV-1a 64 位哈希锁定保护，若被抄袭者删改将自动触发防伪警告）
    static let officialLicenseDeclaration: String = "Calculus3D Open Source Project | Licensed under GPL-3.0 & CC BY-NC-SA 4.0 | 免费供微积分学习与教学使用，严禁抹除署名、严禁抄袭冒充个人作业或商业盗用"

    /// 隐式算法特征种子（供原作者一句话自证底层所有权：0x43414C33445F4F53 = "CAL3D_OS"）
    static let steganographicOwnershipSeed: UInt64 = 0x43414C33445F4F53
    static let expectedDeclarationHash: UInt64 = 0x0C549B62D1AB4050

    /// 实时计算 UTF-8 字符串的 64 位 FNV-1a 指纹
    static func fnv1aHash64(_ text: String) -> UInt64 {
        var hash: UInt64 = 14695981039346656037
        let prime: UInt64 = 1099511628211
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* prime
        }
        return hash
    }

    /// 校验开源署名是否完好未被抄袭者篡改
    static var isSignatureAuthentic: Bool {
        return fnv1aHash64(officialLicenseDeclaration) == expectedDeclarationHash
            && (steganographicOwnershipSeed ^ 0x43414C33445F4F53) == 0
    }

    /// 对计算结果施加防抄袭署名保护：正常使用时原样输出，若署名被恶意删改则叠加防抄袭警示
    static func guardOutput(_ rawOutput: String) -> String {
        if isSignatureAuthentic {
            return rawOutput
        }
        return "⚠️[署名被篡改·严禁抄袭] " + rawOutput
    }
}

// MARK: - 0. iOS 系统设置 (Settings.bundle) 实时同步管理器 (破题提示默认关闭)

final class CalculusAppSettings {
    static let shared = CalculusAppSettings()

    static let kExamHintsEnabled = "com.calculus3d.settings.examHintsEnabled"
    static let kSelfTestMaskEnabled = "com.calculus3d.settings.selfTestMaskEnabled"
    static let kSoundAndHapticsEnabled = "com.calculus3d.settings.soundAndHapticsEnabled"
    static let kSelectedExamPresetIndex = "com.calculus3d.settings.selectedExamPresetIndex"

    func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            CalculusAppSettings.kExamHintsEnabled: false,
            CalculusAppSettings.kSelfTestMaskEnabled: false,
            CalculusAppSettings.kSoundAndHapticsEnabled: true,
            CalculusAppSettings.kSelectedExamPresetIndex: -1
        ])
        UserDefaults.standard.synchronize()
    }

    var isExamHintsEnabled: Bool {
        get { return UserDefaults.standard.bool(forKey: CalculusAppSettings.kExamHintsEnabled) }
        set { UserDefaults.standard.set(newValue, forKey: CalculusAppSettings.kExamHintsEnabled) }
    }

    var isSelfTestMaskEnabled: Bool {
        get { return UserDefaults.standard.bool(forKey: CalculusAppSettings.kSelfTestMaskEnabled) }
        set { UserDefaults.standard.set(newValue, forKey: CalculusAppSettings.kSelfTestMaskEnabled) }
    }

    var isSoundAndHapticsEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: CalculusAppSettings.kSoundAndHapticsEnabled) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: CalculusAppSettings.kSoundAndHapticsEnabled)
        }
        set { UserDefaults.standard.set(newValue, forKey: CalculusAppSettings.kSoundAndHapticsEnabled) }
    }

    var selectedExamPresetIndex: Int {
        get {
            if UserDefaults.standard.object(forKey: CalculusAppSettings.kSelectedExamPresetIndex) == nil {
                return -1
            }
            return UserDefaults.standard.integer(forKey: CalculusAppSettings.kSelectedExamPresetIndex)
        }
        set { UserDefaults.standard.set(newValue, forKey: CalculusAppSettings.kSelectedExamPresetIndex) }
    }

    private init() {
        registerDefaults()
    }
}

// MARK: - 1. 严格分数 / π 符号与小数格式化引擎 (连分数有理逼近，严禁分数与小数混用)

enum ExactMathValueFormatter {

    /// 判断用户原始算式与当前激活的积分上下限中是否显式包含小数点 "."
    static func hasExplicitDecimalInInput(expression: String, boundsRawStrings: [String]) -> Bool {
        if expression.contains(".") { return true }
        for b in boundsRawStrings where b.contains(".") {
            return true
        }
        return false
    }

    /// 使用连分数算法将实数 x 逼近为最简分数 (p, q)，支持任意大分子（如 4000/3）与分母 (1 <= q <= maxDenominator)
    static func approximateFraction(_ value: Double, maxDenominator: Int = 1200, relTolerance: Double = 1.2e-4) -> (Int, Int)? {
        guard value.isFinite else { return nil }
        if abs(value) < 1e-9 { return (0, 1) }

        let sign = value < 0 ? -1 : 1
        let x = abs(value)
        if x > 1e8 { return nil }

        var h0 = 0, k0 = 1
        var h1 = 1, k1 = 0
        var rem = x

        for _ in 0..<18 {
            let a = Int(floor(rem + 1e-11))
            let h2 = a * h1 + h0
            let k2 = a * k1 + k0
            if k2 > maxDenominator { break }

            h0 = h1; k0 = k1
            h1 = h2; k1 = k2

            let approx = Double(h1) / Double(max(1, k1))
            if abs(x - approx) <= relTolerance * max(1.0, x) {
                let g = gcd(h1, k1)
                return (sign * (h1 / g), k1 / g)
            }

            let frac = rem - Double(a)
            if abs(frac) < 1e-9 { break }
            rem = 1.0 / frac
        }
        return nil
    }

    /// 检测是否为 π 的有理数倍 (p/q)·π（如 4π/3、4000π/3、π/5、2π）
    static func formatAsPiMultiple(_ value: Double, tolerance: Double = 1.5e-3) -> String? {
        guard value.isFinite && abs(value) > 1e-6 else { return nil }
        let ratio = value / Double.pi
        guard let (p, q) = approximateFraction(ratio, maxDenominator: 240, relTolerance: tolerance), p != 0 else {
            return nil
        }
        let signStr = p < 0 ? "-" : ""
        let absP = abs(p)
        let piPart = (absP == 1) ? "π" : "\(absP)π"
        return (q == 1) ? "\(signStr)\(piPart)" : "\(signStr)\(piPart)/\(q)"
    }

    /// 根据当前模式（分数符号模式 vs 小数模式）格式化数值，绝不混用分数和小数！
    static func format(_ value: Double, preferFraction: Bool, prefix: String = "") -> String {
        if !value.isFinite { return "\(prefix)发散/未定义" }
        if abs(value) < 1e-7 { return "\(prefix)0" }

        // 若用户使用了小数模式，则全程输出干净的小数，不转写为分数
        if !preferFraction {
            return "\(prefix)\(formatCleanDecimal(value))"
        }

        // 1. 优先匹配精确有理数/整数（如 1/3, 3/4, 3/8, 2）
        if let (p, q) = approximateFraction(value, maxDenominator: 360, relTolerance: 1.2e-4) {
            if q == 1 {
                return "\(prefix)\(p)"
            } else {
                return "\(prefix)\(p)/\(q)"
            }
        }

        // 2. 匹配 π 的有理数倍（如 4π/3, 4000π/3, π/5, π/2）
        if let piStr = formatAsPiMultiple(value) {
            return "\(prefix)\(piStr)"
        }

        // 3. 匹配 √π 或 e 的简单组合（如高斯积分 √π、e - 1）
        let sqrtPiRatio = value / sqrt(Double.pi)
        if let (p, q) = approximateFraction(sqrtPiRatio, maxDenominator: 12, relTolerance: 1.2e-3), p != 0 {
            let s = p < 0 ? "-" : ""
            let absP = abs(p)
            let numStr = (absP == 1) ? "√π" : "\(absP)√π"
            let res = (q == 1) ? "\(s)\(numStr)" : "\(s)\(numStr)/\(q)"
            return "\(prefix)\(res)"
        }

        if abs(value - M_E) < 1.2e-3 { return "\(prefix)e" }
        if abs(value - (M_E - 1.0)) < 1.2e-3 { return "\(prefix)e − 1" }
        if abs(value - (M_E + 1.0)) < 1.2e-3 { return "\(prefix)e + 1" }

        // 4. 若结果本身是超越无理数（如非特殊弧长），回退为数值显示
        return "\(prefix)\(formatCleanDecimal(value))"
    }

    static func formatCleanDecimal(_ value: Double) -> String {
        if abs(value) < 1e-7 { return "0" }
        if abs(value - round(value)) < 1e-6 {
            return "\(Int(round(value)))"
        }
        var s = String(format: "%.4f", value)
        while s.contains(".") && (s.hasSuffix("0") || s.hasSuffix(".")) {
            let last = s.removeLast()
            if last == "." { break }
        }
        return s
    }

    static func gcd(_ a: Int, _ b: Int) -> Int {
        var x = abs(a)
        var y = abs(b)
        while y != 0 {
            let t = x % y
            x = y
            y = t
        }
        return max(1, x)
    }
}

// MARK: - 2. iPhone X 硬件触觉与原生按键音管理器

final class TactileFeedbackManager {
    static let shared = TactileFeedbackManager()

    private let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private let heavyImpact = UIImpactFeedbackGenerator(style: .heavy)
    private let selectionFeedback = UISelectionFeedbackGenerator()

    private init() {
        prepareAll()
    }

    func prepareAll() {
        lightImpact.prepare()
        mediumImpact.prepare()
        heavyImpact.prepare()
        selectionFeedback.prepare()
    }

    func playKeyTap() {
        guard CalculusAppSettings.shared.isSoundAndHapticsEnabled else { return }
        AudioServicesPlaySystemSound(1104)
        lightImpact.impactOccurred()
        lightImpact.prepare()
    }

    func playDeleteTap() {
        guard CalculusAppSettings.shared.isSoundAndHapticsEnabled else { return }
        AudioServicesPlaySystemSound(1155)
        mediumImpact.impactOccurred()
        mediumImpact.prepare()
    }

    func playModifierTap() {
        guard CalculusAppSettings.shared.isSoundAndHapticsEnabled else { return }
        AudioServicesPlaySystemSound(1156)
        selectionFeedback.selectionChanged()
        selectionFeedback.prepare()
    }

    func playAxisSnapDetent() {
        guard CalculusAppSettings.shared.isSoundAndHapticsEnabled else { return }
        selectionFeedback.selectionChanged()
        selectionFeedback.prepare()
    }

    func play3DTouchPeek() {
        guard CalculusAppSettings.shared.isSoundAndHapticsEnabled else { return }
        AudioServicesPlaySystemSound(1519)
        mediumImpact.impactOccurred()
    }

    func play3DTouchDeepPop() {
        guard CalculusAppSettings.shared.isSoundAndHapticsEnabled else { return }
        AudioServicesPlaySystemSound(1520)
        heavyImpact.impactOccurred()
        heavyImpact.prepare()
    }
}

// MARK: - 3. 原版一体式矢量计算器按键

enum CalcKeyStyle: Int {
    case digit = 0
    case orangeOperator = 1
    case lightFunction = 2
    case variableKey = 3
    case mathFunction = 4
}

final class CalculatorIntegratedKeyButton: UIControl {

    let primaryToken: String
    let secondaryForceToken: String?
    private let keyStyle: CalcKeyStyle
    private let displaySymbol: String

    var onLightTap: ((String) -> Void)?
    var onForceDeepPress: ((String) -> Void)?

    private let mainSymbolLabel = UILabel()
    private let secondaryForceLabel = UILabel()

    private var normalBgColor: UIColor = .darkGray
    private var highlightedBgColor: UIColor = .lightGray

    private var hasTriggeredForceAction = false
    private var hasTriggeredPeekHint = false

    init(primary: String, displaySymbol: String? = nil, secondaryForce: String? = nil, style: CalcKeyStyle) {
        self.primaryToken = primary
        self.displaySymbol = displaySymbol ?? primary
        self.secondaryForceToken = secondaryForce
        self.keyStyle = style
        super.init(frame: .zero)

        layer.cornerRadius = 14
        layer.masksToBounds = true
        configureColorsAndTypography()
        setupLabels()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureColorsAndTypography() {
        switch keyStyle {
        case .digit:
            normalBgColor = UIColor(red: 0.20, green: 0.20, blue: 0.21, alpha: 1.0)
            highlightedBgColor = UIColor(red: 0.45, green: 0.45, blue: 0.47, alpha: 1.0)
            mainSymbolLabel.textColor = .white
            secondaryForceLabel.textColor = UIColor(red: 1.0, green: 0.68, blue: 0.20, alpha: 0.90)

        case .orangeOperator:
            normalBgColor = UIColor(red: 1.0, green: 0.584, blue: 0.0, alpha: 1.0)
            highlightedBgColor = UIColor(red: 1.0, green: 0.80, blue: 0.48, alpha: 1.0)
            mainSymbolLabel.textColor = .white
            secondaryForceLabel.textColor = UIColor(white: 1.0, alpha: 0.90)

        case .lightFunction:
            normalBgColor = UIColor(red: 0.65, green: 0.65, blue: 0.67, alpha: 1.0)
            highlightedBgColor = UIColor(red: 0.85, green: 0.85, blue: 0.87, alpha: 1.0)
            mainSymbolLabel.textColor = .black
            secondaryForceLabel.textColor = UIColor(white: 0.15, alpha: 0.85)

        case .variableKey:
            normalBgColor = UIColor(red: 0.14, green: 0.38, blue: 0.82, alpha: 1.0)
            highlightedBgColor = UIColor(red: 0.30, green: 0.56, blue: 0.96, alpha: 1.0)
            mainSymbolLabel.textColor = .white
            secondaryForceLabel.textColor = UIColor(red: 0.82, green: 0.92, blue: 1.0, alpha: 0.95)

        case .mathFunction:
            normalBgColor = UIColor(red: 0.13, green: 0.13, blue: 0.15, alpha: 1.0)
            highlightedBgColor = UIColor(red: 0.30, green: 0.30, blue: 0.33, alpha: 1.0)
            mainSymbolLabel.textColor = UIColor(white: 0.96, alpha: 1.0)
            secondaryForceLabel.textColor = UIColor(red: 1.0, green: 0.65, blue: 0.18, alpha: 0.88)
        }

        backgroundColor = normalBgColor
        updateFontsForCurrentHeight(52.0)
    }

    private func updateFontsForCurrentHeight(_ h: CGFloat) {
        let scale = max(0.68, min(1.05, h / 52.0))
        if keyStyle == .orangeOperator {
            mainSymbolLabel.font = UIFont.systemFont(ofSize: round(25.0 * scale), weight: .regular)
        } else if keyStyle == .digit {
            mainSymbolLabel.font = UIFont.systemFont(ofSize: round(23.0 * scale), weight: .regular)
        } else if keyStyle == .variableKey {
            let sz = round(21.0 * scale)
            mainSymbolLabel.font = UIFont(name: "TimesNewRomanPS-BoldItalicMT", size: sz)
                ?? UIFont.italicSystemFont(ofSize: sz)
        } else if keyStyle == .lightFunction {
            mainSymbolLabel.font = UIFont.systemFont(ofSize: round(18.5 * scale), weight: .semibold)
        } else {
            let base: CGFloat = (displaySymbol.count > 2) ? 16.0 : 18.5
            mainSymbolLabel.font = UIFont.systemFont(ofSize: round(base * scale), weight: .medium)
        }
        secondaryForceLabel.font = UIFont.systemFont(ofSize: max(8.5, round(10.0 * scale)), weight: .semibold)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let minDim = min(bounds.width, bounds.height)
        if minDim > 10 {
            layer.cornerRadius = min(15.0, max(9.0, minDim * 0.28))
            updateFontsForCurrentHeight(bounds.height)
        }
    }

    private func setupLabels() {
        mainSymbolLabel.text = displaySymbol
        mainSymbolLabel.textAlignment = .center
        mainSymbolLabel.isUserInteractionEnabled = false
        mainSymbolLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(mainSymbolLabel)

        secondaryForceLabel.text = secondaryForceToken ?? ""
        secondaryForceLabel.textAlignment = .right
        secondaryForceLabel.isHidden = (secondaryForceToken == nil)
        secondaryForceLabel.isUserInteractionEnabled = false
        secondaryForceLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(secondaryForceLabel)

        NSLayoutConstraint.activate([
            mainSymbolLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            mainSymbolLabel.centerYAnchor.constraint(equalTo: centerYAnchor, constant: secondaryForceToken != nil ? 2 : 0),

            secondaryForceLabel.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            secondaryForceLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6)
        ])
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        hasTriggeredForceAction = false
        hasTriggeredPeekHint = false

        if primaryToken == "⌫" || primaryToken == "AC" {
            TactileFeedbackManager.shared.playDeleteTap()
        } else if keyStyle == .orangeOperator {
            TactileFeedbackManager.shared.playModifierTap()
        } else {
            TactileFeedbackManager.shared.playKeyTap()
        }

        UIView.animate(withDuration: 0.05, delay: 0, options: [.allowUserInteraction], animations: {
            self.backgroundColor = self.highlightedBgColor
            self.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)
        }, completion: nil)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        guard let touch = touches.first,
              traitCollection.forceTouchCapability == .available,
              touch.maximumPossibleForce > 0 else {
            return
        }

        let normalizedForce = touch.force / touch.maximumPossibleForce
        if !hasTriggeredForceAction {
            let s = CGFloat(0.96 - 0.06 * min(1.0, max(0.0, normalizedForce)))
            self.transform = CGAffineTransform(scaleX: s, y: s)
        }

        if let sec = secondaryForceToken {
            if normalizedForce >= 0.42 && !hasTriggeredPeekHint {
                hasTriggeredPeekHint = true
                TactileFeedbackManager.shared.play3DTouchPeek()
                secondaryForceLabel.transform = CGAffineTransform(scaleX: 1.18, y: 1.18)
            }
            if normalizedForce >= 0.68 && !hasTriggeredForceAction {
                hasTriggeredForceAction = true
                TactileFeedbackManager.shared.play3DTouchDeepPop()

                backgroundColor = UIColor(red: 1.0, green: 0.584, blue: 0.0, alpha: 1.0)
                mainSymbolLabel.text = sec
                UIView.animate(withDuration: 0.08) {
                    self.transform = CGAffineTransform(scaleX: 1.05, y: 1.05)
                }
                onForceDeepPress?(sec)
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        if !hasTriggeredForceAction {
            onLightTap?(primaryToken)
        }
        restoreKeycap()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        restoreKeycap()
    }

    private func restoreKeycap() {
        mainSymbolLabel.text = displaySymbol
        UIView.animate(withDuration: 0.15, delay: 0, options: [.allowUserInteraction, .curveEaseOut], animations: {
            self.backgroundColor = self.normalBgColor
            self.transform = .identity
            self.secondaryForceLabel.transform = .identity
        }, completion: nil)
    }
}

// MARK: - 4. 纯黑主题上下限胶囊填空控件

final class BoundsInputButton: UIControl {

    let titleLabel = UILabel()
    let valueLabel = UILabel()

    var rawExpression: String {
        didSet {
            let display = rawExpression.isEmpty ? "0" : NaturalMathFormatter.prettifyForDisplay(rawExpression)
            valueLabel.text = display
        }
    }

    var isActiveInput: Bool = false {
        didSet {
            updateHighlightStyle()
        }
    }

    var shouldOverwriteOnNextChar: Bool = false

    init(title: String, initialValue: String) {
        self.rawExpression = initialValue
        super.init(frame: .zero)

        layer.cornerRadius = 10
        layer.masksToBounds = true

        titleLabel.text = title
        titleLabel.font = UIFont.systemFont(ofSize: 10.5, weight: .medium)
        titleLabel.isUserInteractionEnabled = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        valueLabel.text = NaturalMathFormatter.prettifyForDisplay(initialValue)
        valueLabel.font = UIFont.systemFont(ofSize: 13.5, weight: .semibold)
        valueLabel.textColor = .white
        valueLabel.textAlignment = .right
        valueLabel.isUserInteractionEnabled = false
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(valueLabel)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            valueLabel.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 3),
            valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            valueLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        updateHighlightStyle()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var numericValue: Double {
        let normalized = rawExpression.replacingOccurrences(of: "−", with: "-")
        if let direct = Double(normalized) {
            return direct
        }
        let fn = MultivariateMathParser.compileSafe3D(normalized)
        let v = fn(0, 0, 0)
        return v.isFinite ? v : 0.0
    }

    private func updateHighlightStyle() {
        if isActiveInput {
            backgroundColor = UIColor(red: 0.22, green: 0.16, blue: 0.06, alpha: 1.0)
            layer.borderWidth = 1.5
            layer.borderColor = UIColor(red: 1.0, green: 0.584, blue: 0.0, alpha: 1.0).cgColor
            titleLabel.textColor = UIColor(red: 1.0, green: 0.68, blue: 0.20, alpha: 1.0)
        } else {
            backgroundColor = UIColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1.0)
            layer.borderWidth = 0.8
            layer.borderColor = UIColor(red: 0.24, green: 0.24, blue: 0.26, alpha: 1.0).cgColor
            titleLabel.textColor = UIColor(white: 0.60, alpha: 1.0)
        }
    }
}

// MARK: - 5. 全内置数学特殊函数库

enum BuiltinSpecialMath {
    @inline(__always)
    static func erfApprox(_ x: Double) -> Double {
        let sign = x < 0 ? -1.0 : 1.0
        let ax = abs(x)
        let p = 0.3275911
        let a1 = 0.254829592
        let a2 = -0.284496736
        let a3 = 1.421413741
        let a4 = -1.453152027
        let a5 = 1.061405429
        let t = 1.0 / (1.0 + p * ax)
        let poly = (((((a5 * t + a4) * t) + a3) * t + a2) * t + a1) * t
        return sign * (1.0 - poly * exp(-ax * ax))
    }

    static func gammaLanczos(_ z: Double) -> Double {
        if z <= 0.0 && abs(z - round(z)) < 1e-7 { return Double.nan }
        if z < 0.5 { return Double.pi / (sin(Double.pi * z) * gammaLanczos(1.0 - z)) }
        let g = 7.0
        let p0 = 0.99999999999980993
        let p1 = 676.5203681218851
        let p2 = -1259.1392167224028
        let p3 = 771.32342877765313
        let p4 = -176.61502916214059
        let p5 = 12.507343278686905
        let p6 = -0.13857109526572012
        let p7 = 9.9843695780195716e-6
        let p8 = 1.5056327351493116e-7

        let zm1 = z - 1.0
        let x = p0 + p1/(zm1+1) + p2/(zm1+2) + p3/(zm1+3) + p4/(zm1+4)
                   + p5/(zm1+5) + p6/(zm1+6) + p7/(zm1+7) + p8/(zm1+8)
        let t = zm1 + g + 0.5
        return sqrt(2.0 * Double.pi) * pow(t, zm1 + 0.5) * exp(-t) * x
    }
}

// MARK: - 6. 精确有理分数符号微积分引擎 (保留 3/4, 1/3 等精确分数，绝不擅自改成小数)

indirect enum MathAST {
    case number(Double)
    case symbolicConst(String, Double)
    case varX
    case varY
    case varZ
    case neg(MathAST)
    case add(MathAST, MathAST)
    case sub(MathAST, MathAST)
    case mul(MathAST, MathAST)
    case div(MathAST, MathAST)
    case pow(MathAST, MathAST)
    case call(String, MathAST)
}

enum RPNInstruction {
    case pushConst(Double)
    case pushX
    case pushY
    case pushZ
    case neg
    case add, sub, mul, div, pow
    case sin, cos, tan, asin, acos, atan
    case sinh, cosh, tanh
    case exp, ln, sqrt, abs
    case erf, gamma
}

final class SymbolicCalculusEngine {

    static func compileToRPN(_ node: MathAST, into code: inout [RPNInstruction]) {
        switch node {
        case .number(let v):
            code.append(.pushConst(v))
        case .symbolicConst(_, let v):
            code.append(.pushConst(v))
        case .varX:
            code.append(.pushX)
        case .varY:
            code.append(.pushY)
        case .varZ:
            code.append(.pushZ)
        case .neg(let a):
            compileToRPN(a, into: &code)
            code.append(.neg)
        case .add(let a, let b):
            compileToRPN(a, into: &code)
            compileToRPN(b, into: &code)
            code.append(.add)
        case .sub(let a, let b):
            compileToRPN(a, into: &code)
            compileToRPN(b, into: &code)
            code.append(.sub)
        case .mul(let a, let b):
            compileToRPN(a, into: &code)
            compileToRPN(b, into: &code)
            code.append(.mul)
        case .div(let a, let b):
            compileToRPN(a, into: &code)
            compileToRPN(b, into: &code)
            code.append(.div)
        case .pow(let a, let b):
            compileToRPN(a, into: &code)
            compileToRPN(b, into: &code)
            code.append(.pow)
        case .call(let fn, let a):
            compileToRPN(a, into: &code)
            switch fn {
            case "sin":   code.append(.sin)
            case "cos":   code.append(.cos)
            case "tan":   code.append(.tan)
            case "asin":  code.append(.asin)
            case "acos":  code.append(.acos)
            case "atan":  code.append(.atan)
            case "sinh":  code.append(.sinh)
            case "cosh":  code.append(.cosh)
            case "tanh":  code.append(.tanh)
            case "exp":   code.append(.exp)
            case "ln":    code.append(.ln)
            case "sqrt":  code.append(.sqrt)
            case "abs":   code.append(.abs)
            case "erf":   code.append(.erf)
            case "gamma": code.append(.gamma)
            default: break
            }
        }
    }

    @inline(__always)
    static func evalRPN(_ code: [RPNInstruction], x: Double, y: Double, z: Double) -> Double {
        var s: (Double, Double, Double, Double, Double, Double, Double, Double,
                Double, Double, Double, Double, Double, Double, Double, Double) =
               (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        var sp = 0

        return withUnsafeMutablePointer(to: &s) { ptr -> Double in
            let stack = UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: Double.self)
            for ins in code {
                switch ins {
                case .pushConst(let v):
                    if sp < 16 { stack[sp] = v; sp += 1 }
                case .pushX:
                    if sp < 16 { stack[sp] = x; sp += 1 }
                case .pushY:
                    if sp < 16 { stack[sp] = y; sp += 1 }
                case .pushZ:
                    if sp < 16 { stack[sp] = z; sp += 1 }
                case .neg:
                    if sp > 0 { stack[sp - 1] = -stack[sp - 1] }
                case .add:
                    if sp >= 2 { sp -= 1; stack[sp - 1] += stack[sp] }
                case .sub:
                    if sp >= 2 { sp -= 1; stack[sp - 1] -= stack[sp] }
                case .mul:
                    if sp >= 2 { sp -= 1; stack[sp - 1] *= stack[sp] }
                case .div:
                    if sp >= 2 { sp -= 1; stack[sp - 1] /= stack[sp] }
                case .pow:
                    if sp >= 2 { sp -= 1; stack[sp - 1] = Foundation.pow(stack[sp - 1], stack[sp]) }
                case .sin:
                    if sp > 0 { stack[sp - 1] = Foundation.sin(stack[sp - 1]) }
                case .cos:
                    if sp > 0 { stack[sp - 1] = Foundation.cos(stack[sp - 1]) }
                case .tan:
                    if sp > 0 { stack[sp - 1] = Foundation.tan(stack[sp - 1]) }
                case .asin:
                    if sp > 0 { stack[sp - 1] = Foundation.asin(stack[sp - 1]) }
                case .acos:
                    if sp > 0 { stack[sp - 1] = Foundation.acos(stack[sp - 1]) }
                case .atan:
                    if sp > 0 { stack[sp - 1] = Foundation.atan(stack[sp - 1]) }
                case .sinh:
                    if sp > 0 { stack[sp - 1] = Foundation.sinh(stack[sp - 1]) }
                case .cosh:
                    if sp > 0 { stack[sp - 1] = Foundation.cosh(stack[sp - 1]) }
                case .tanh:
                    if sp > 0 { stack[sp - 1] = Foundation.tanh(stack[sp - 1]) }
                case .exp:
                    if sp > 0 { stack[sp - 1] = Foundation.exp(stack[sp - 1]) }
                case .ln:
                    if sp > 0 { stack[sp - 1] = Foundation.log(stack[sp - 1]) }
                case .sqrt:
                    if sp > 0 { stack[sp - 1] = Foundation.sqrt(stack[sp - 1]) }
                case .abs:
                    if sp > 0 { stack[sp - 1] = Swift.abs(stack[sp - 1]) }
                case .erf:
                    if sp > 0 { stack[sp - 1] = BuiltinSpecialMath.erfApprox(stack[sp - 1]) }
                case .gamma:
                    if sp > 0 { stack[sp - 1] = BuiltinSpecialMath.gammaLanczos(stack[sp - 1]) }
                }
            }
            return sp > 0 ? stack[0] : 0.0
        }
    }

    static func containsVar(_ node: MathAST, _ v: String) -> Bool {
        switch node {
        case .number, .symbolicConst: return false
        case .varX: return v == "x"
        case .varY: return v == "y"
        case .varZ: return v == "z"
        case .neg(let a), .call(_, let a):
            return containsVar(a, v)
        case .add(let a, let b), .sub(let a, let b),
             .mul(let a, let b), .div(let a, let b), .pow(let a, let b):
            return containsVar(a, v) || containsVar(b, v)
        }
    }

    /// 提取 AST 节点中的精确整数或有理分数 (分子, 分母)，用于精确分数化简（如 3/4 * 1/2 = 3/8，绝不变成 0.375）
    private static func extractExactRational(_ node: MathAST) -> (Int, Int)? {
        switch node {
        case .number(let v):
            if abs(v) < 1e7 && abs(v - round(v)) < 1e-9 {
                return (Int(round(v)), 1)
            }
            return nil
        case .neg(let inner):
            if let (p, q) = extractExactRational(inner) {
                return (-p, q)
            }
            return nil
        case .div(let a, let b):
            if case .number(let va) = a, case .number(let vb) = b,
               abs(va) < 1e7, abs(vb) < 1e7,
               abs(va - round(va)) < 1e-9, abs(vb - round(vb)) < 1e-9 {
                let p = Int(round(va))
                let q = Int(round(vb))
                guard q != 0 else { return nil }
                let sign = (q < 0) ? -1 : 1
                let g = ExactMathValueFormatter.gcd(p, q)
                return (sign * (p / g), abs(q) / g)
            }
            return nil
        default:
            return nil
        }
    }

    private static func makeRationalNode(p: Int, q: Int) -> MathAST {
        guard q != 0 else { return .number(0) }
        if p == 0 { return .number(0) }
        let sign = (q < 0) ? -1 : 1
        let g = ExactMathValueFormatter.gcd(p, q)
        let np = sign * (p / g)
        let nq = abs(q) / g
        if nq == 1 {
            return .number(Double(np))
        }
        return .div(.number(Double(np)), .number(Double(nq)))
    }

    static func differentiate(_ node: MathAST, wrt v: String) -> MathAST {
        switch node {
        case .number, .symbolicConst:
            return .number(0)
        case .varX:
            return .number(v == "x" ? 1 : 0)
        case .varY:
            return .number(v == "y" ? 1 : 0)
        case .varZ:
            return .number(v == "z" ? 1 : 0)
        case .neg(let a):
            return .neg(differentiate(a, wrt: v))
        case .add(let a, let b):
            return .add(differentiate(a, wrt: v), differentiate(b, wrt: v))
        case .sub(let a, let b):
            return .sub(differentiate(a, wrt: v), differentiate(b, wrt: v))
        case .mul(let a, let b):
            return .add(.mul(differentiate(a, wrt: v), b), .mul(a, differentiate(b, wrt: v)))
        case .div(let a, let b):
            if !containsVar(b, v) {
                return .div(differentiate(a, wrt: v), b)
            }
            let num = MathAST.sub(.mul(differentiate(a, wrt: v), b), .mul(a, differentiate(b, wrt: v)))
            return .div(num, .pow(b, .number(2)))
        case .pow(let base, let expNode):
            let baseHasV = containsVar(base, v)
            let expHasV = containsVar(expNode, v)
            if !baseHasV && !expHasV { return .number(0) }
            if !expHasV {
                let dBase = differentiate(base, wrt: v)
                return .mul(.mul(expNode, .pow(base, .sub(expNode, .number(1)))), dBase)
            }
            if !baseHasV {
                let dExp = differentiate(expNode, wrt: v)
                return .mul(.mul(node, .call("ln", base)), dExp)
            }
            return .mul(node, differentiate(.mul(expNode, .call("ln", base)), wrt: v))
        case .call(let fn, let arg):
            let dArg = differentiate(arg, wrt: v)
            let outer: MathAST
            switch fn {
            case "sin":  outer = .call("cos", arg)
            case "cos":  outer = .neg(.call("sin", arg))
            case "tan":  outer = .div(.number(1), .pow(.call("cos", arg), .number(2)))
            case "asin": outer = .div(.number(1), .call("sqrt", .sub(.number(1), .pow(arg, .number(2)))))
            case "acos": outer = .neg(.div(.number(1), .call("sqrt", .sub(.number(1), .pow(arg, .number(2))))))
            case "atan": outer = .div(.number(1), .add(.number(1), .pow(arg, .number(2))))
            case "sinh": outer = .call("cosh", arg)
            case "cosh": outer = .call("sinh", arg)
            case "tanh": outer = .div(.number(1), .pow(.call("cosh", arg), .number(2)))
            case "exp":  outer = .call("exp", arg)
            case "ln":   outer = .div(.number(1), arg)
            case "sqrt": outer = .div(.number(1), .mul(.number(2), .call("sqrt", arg)))
            case "erf":  outer = .mul(.number(2.0 / sqrt(Double.pi)), .call("exp", .neg(.pow(arg, .number(2)))))
            default:     outer = .number(1)
            }
            return .mul(outer, dArg)
        }
    }

    static func simplify(_ node: MathAST) -> MathAST {
        var current = node
        for _ in 0..<5 {
            current = simplifyOnce(current)
        }
        return current
    }

    private static func simplifyOnce(_ node: MathAST) -> MathAST {
        switch node {
        case .number, .symbolicConst, .varX, .varY, .varZ:
            return node
        case .neg(let a):
            let sa = simplifyOnce(a)
            if case .number(let v) = sa { return .number(-v) }
            if case .neg(let inner) = sa { return inner }
            return .neg(sa)
        case .add(let a, let b):
            let sa = simplifyOnce(a)
            let sb = simplifyOnce(b)
            if let (p1, q1) = extractExactRational(sa), let (p2, q2) = extractExactRational(sb) {
                return makeRationalNode(p: p1 * q2 + p2 * q1, q: q1 * q2)
            }
            if case .number(let va) = sa, case .number(let vb) = sb { return .number(va + vb) }
            if case .number(let va) = sa, abs(va) < 1e-12 { return sb }
            if case .number(let vb) = sb, abs(vb) < 1e-12 { return sa }
            return .add(sa, sb)
        case .sub(let a, let b):
            let sa = simplifyOnce(a)
            let sb = simplifyOnce(b)
            if let (p1, q1) = extractExactRational(sa), let (p2, q2) = extractExactRational(sb) {
                return makeRationalNode(p: p1 * q2 - p2 * q1, q: q1 * q2)
            }
            if case .number(let va) = sa, case .number(let vb) = sb { return .number(va - vb) }
            if case .number(let vb) = sb, abs(vb) < 1e-12 { return sa }
            if case .number(let va) = sa, abs(va) < 1e-12 { return .neg(sb) }
            return .sub(sa, sb)
        case .mul(let a, let b):
            let sa = simplifyOnce(a)
            let sb = simplifyOnce(b)
            if let (p1, q1) = extractExactRational(sa), let (p2, q2) = extractExactRational(sb) {
                return makeRationalNode(p: p1 * p2, q: q1 * q2)
            }
            // 处理 (p1/q1) * ((p2/q2) * expr) 合并分数系数（如 3/4 * (1/2 * x²) -> 3/8 * x²）
            if let (p1, q1) = extractExactRational(sa), case .mul(let innerCoeff, let rest) = sb, let (p2, q2) = extractExactRational(innerCoeff) {
                return .mul(makeRationalNode(p: p1 * p2, q: q1 * q2), rest)
            }
            if let (p1, q1) = extractExactRational(sa), case .div(let numExpr, let denCoeff) = sb, let (p2, q2) = extractExactRational(denCoeff) {
                return .mul(makeRationalNode(p: p1 * q2, q: q1 * p2), numExpr)
            }
            if case .number(let va) = sa, case .number(let vb) = sb { return .number(va * vb) }
            if case .number(let va) = sa {
                if abs(va) < 1e-12 { return .number(0) }
                if abs(va - 1.0) < 1e-12 { return sb }
                if abs(va + 1.0) < 1e-12 { return .neg(sb) }
            }
            if case .number(let vb) = sb {
                if abs(vb) < 1e-12 { return .number(0) }
                if abs(vb - 1.0) < 1e-12 { return sa }
                if abs(vb + 1.0) < 1e-12 { return .neg(sa) }
            }
            return .mul(sa, sb)
        case .div(let a, let b):
            let sa = simplifyOnce(a)
            let sb = simplifyOnce(b)
            // 若分子分母均为整数或分数，化为最简分数 (如 6/8 -> 3/4，4/2 -> 2)，绝不转成小数 0.75！
            if let (p1, q1) = extractExactRational(sa), let (p2, q2) = extractExactRational(sb), p2 != 0 {
                return makeRationalNode(p: p1 * q2, q: q1 * p2)
            }
            if case .number(let va) = sa, abs(va) < 1e-12 { return .number(0) }
            if case .number(let vb) = sb, abs(vb - 1.0) < 1e-12 { return sa }
            return .div(sa, sb)
        case .pow(let a, let b):
            let sa = simplifyOnce(a)
            let sb = simplifyOnce(b)
            if case .number(let vb) = sb {
                if abs(vb) < 1e-12 { return .number(1) }
                if abs(vb - 1.0) < 1e-12 { return sa }
                if let (p, q) = extractExactRational(sa), abs(vb - round(vb)) < 1e-9, vb > 0, vb <= 6 {
                    let e = Int(round(vb))
                    let np = Int(Foundation.pow(Double(p), Double(e)))
                    let nq = Int(Foundation.pow(Double(q), Double(e)))
                    return makeRationalNode(p: np, q: nq)
                }
            }
            return .pow(sa, sb)
        case .call(let fn, let a):
            let sa = simplifyOnce(a)
            if fn == "exp" {
                if case .number(let v) = sa {
                    if abs(v) < 1e-12 { return .number(1) }
                    if abs(v - 1.0) < 1e-12 { return .symbolicConst("e", M_E) }
                }
            } else if fn == "ln" {
                if case .symbolicConst(let sym, _) = sa, sym == "e" { return .number(1) }
                if case .number(let v) = sa, abs(v - 1.0) < 1e-12 { return .number(0) }
            } else if fn == "sqrt", case .number(let v) = sa, v >= 0 {
                let r = Foundation.sqrt(v)
                if abs(r - round(r)) < 1e-9 { return .number(round(r)) }
            }
            return .call(fn, sa)
        }
    }

    static func integrateSymbolicWithStepsWrtX(
        _ node: MathAST,
        a: Double,
        b: Double,
        numResult: Double,
        preferFraction: Bool
    ) -> (antiderivative: String, examStepsExplanation: String) {
        let sNode = simplify(node)
        let aStr = ExactMathValueFormatter.format(a, preferFraction: preferFraction)
        let bStr = ExactMathValueFormatter.format(b, preferFraction: preferFraction)
        let exactResStr = ExactMathValueFormatter.format(numResult, preferFraction: preferFraction)

        if let (antiAST, stepDesc) = tryAntiderivativeWithStep(sNode, preferFraction: preferFraction) {
            let simpAnti = simplify(antiAST)
            let formatted = format(simpAnti, preferFraction: preferFraction)
            var rpn: [RPNInstruction] = []
            compileToRPN(simpAnti, into: &rpn)
            let fb = evalRPN(rpn, x: b, y: 0, z: 0)
            let fa = evalRPN(rpn, x: a, y: 0, z: 0)
            let fbStr = ExactMathValueFormatter.format(fb, preferFraction: preferFraction)
            let faStr = (fa < 0) ? "(\(ExactMathValueFormatter.format(fa, preferFraction: preferFraction)))" : ExactMathValueFormatter.format(fa, preferFraction: preferFraction)

            let steps = """
            ① 不定积分原函数：\(stepDesc) ⇒ F(x) = \(formatted) + C
            ② 牛顿-莱布尼茨代入：F(\(bStr)) − F(\(aStr)) = \(fbStr) − \(faStr) = \(exactResStr)
            """
            return (formatted + " + C", steps)
        }
        let fallbackSteps = """
        ① 原函数分析：被积函数无初等原函数或属多元重积分
        ② 积分结果：在 [\(aStr), \(bStr)] 上 I = \(exactResStr)
        """
        return ("非初等/多元积分", fallbackSteps)
    }

    private static func tryAntiderivativeWithStep(_ node: MathAST, preferFraction: Bool) -> (MathAST, String)? {
        if !containsVar(node, "x") {
            return (.mul(node, .varX), "常数因子法则 ∫ C dx = C·x")
        }
        switch node {
        case .varX:
            if preferFraction {
                return (.div(.pow(.varX, .number(2)), .number(2)), "幂函数公式 ∫ x dx = x²/2")
            } else {
                return (.mul(.number(0.5), .pow(.varX, .number(2))), "幂函数公式 ∫ x dx = 0.5x²")
            }
        case .neg(let a):
            if let (ia, st) = tryAntiderivativeWithStep(a, preferFraction: preferFraction) { return (.neg(ia), st) }
            return nil
        case .add(let a, let b):
            if let (ia, s1) = tryAntiderivativeWithStep(a, preferFraction: preferFraction),
               let (ib, _) = tryAntiderivativeWithStep(b, preferFraction: preferFraction) {
                return (.add(ia, ib), "分项积分 (\(s1))")
            }
            return nil
        case .sub(let a, let b):
            if let (ia, s1) = tryAntiderivativeWithStep(a, preferFraction: preferFraction),
               let (ib, _) = tryAntiderivativeWithStep(b, preferFraction: preferFraction) {
                return (.sub(ia, ib), "分项积分 (\(s1))")
            }
            return nil
        case .mul(let a, let b):
            if !containsVar(a, "x"), let (ib, st) = tryAntiderivativeWithStep(b, preferFraction: preferFraction) {
                return (.mul(a, ib), "提出常数因子 + \(st)")
            }
            if !containsVar(b, "x"), let (ia, st) = tryAntiderivativeWithStep(a, preferFraction: preferFraction) {
                return (.mul(b, ia), "提出常数因子 + \(st)")
            }
            if case .varX = a, case .call(let fn, let arg) = b, case .varX = arg {
                if fn == "exp" {
                    return (.mul(.sub(.varX, .number(1)), .call("exp", .varX)), "分部积分法：令 u=x, dv=eˣdx")
                } else if fn == "sin" {
                    return (.sub(.call("sin", .varX), .mul(.varX, .call("cos", .varX))), "分部积分法：令 u=x, dv=sin(x)dx")
                } else if fn == "cos" {
                    return (.add(.call("cos", .varX), .mul(.varX, .call("sin", .varX))), "分部积分法：令 u=x, dv=cos(x)dx")
                }
            }
            return nil
        case .div(let a, let b):
            if !containsVar(b, "x"), let (ia, st) = tryAntiderivativeWithStep(a, preferFraction: preferFraction) {
                return (.div(ia, b), st)
            }
            if !containsVar(a, "x"), case .varX = b {
                return (.mul(a, .call("ln", .call("abs", .varX))), "对数公式 ∫ a/x dx = a·ln|x|")
            }
            return nil
        case .pow(let base, let expNode):
            if case .varX = base {
                if let (p, q) = extractExactRational(expNode) {
                    if p == -q {
                        return (.call("ln", .call("abs", .varX)), "对数公式 ∫ x⁻¹ dx = ln|x|")
                    }
                    let newP = p + q
                    let newExp = makeRationalNode(p: newP, q: q)
                    let coeff = makeRationalNode(p: q, q: newP)
                    if q == 1 && preferFraction {
                        return (.div(.pow(.varX, newExp), .number(Double(newP))), "幂函数公式 ∫ xⁿ dx = xⁿ⁺¹/(n+1)")
                    }
                    return (.mul(coeff, .pow(.varX, newExp)), "幂函数公式 ∫ xⁿ dx = xⁿ⁺¹/(n+1)")
                } else if case .number(let n) = expNode {
                    if abs(n + 1.0) < 1e-9 {
                        return (.call("ln", .call("abs", .varX)), "对数公式 ∫ x⁻¹ dx = ln|x|")
                    }
                    return (.div(.pow(.varX, .number(n + 1.0)), .number(n + 1.0)), "幂函数公式 ∫ xⁿ dx = xⁿ⁺¹/(n+1)")
                }
            }
            return nil
        case .call(let fn, let arg):
            if case .varX = arg {
                switch fn {
                case "sin":  return (.neg(.call("cos", .varX)), "基本三角公式 ∫ sin(x)dx = −cos(x)")
                case "cos":  return (.call("sin", .varX), "基本三角公式 ∫ cos(x)dx = sin(x)")
                case "exp":  return (.call("exp", .varX), "指数公式 ∫ eˣ dx = eˣ")
                case "ln":   return (.sub(.mul(.varX, .call("ln", .varX)), .varX), "分部积分令 u=ln(x), dv=dx")
                case "sinh": return (.call("cosh", .varX), "双曲公式 ∫ sinh(x)dx = cosh(x)")
                case "cosh": return (.call("sinh", .varX), "双曲公式 ∫ cosh(x)dx = sinh(x)")
                case "sqrt":
                    if preferFraction {
                        let twoThirds = MathAST.div(.number(2), .number(3))
                        let threeHalves = MathAST.div(.number(3), .number(2))
                        return (.mul(twoThirds, .pow(.varX, threeHalves)), "根式幂积分 ∫ √x dx = (2/3)x^(3/2)")
                    } else {
                        return (.mul(.number(2.0 / 3.0), .pow(.varX, .number(1.5))), "根式幂积分 ∫ √x dx = 0.667x^(1.5)")
                    }
                default: return nil
                }
            }
            return nil
        default:
            return nil
        }
    }

    static func format(_ node: MathAST, preferFraction: Bool = true) -> String {
        switch node {
        case .number(let v):
            if abs(v - Double.pi) < 1e-6 { return "π" }
            if abs(v - M_E) < 1e-6 { return "e" }
            if abs(v - round(v)) < 1e-9 { return "\(Int(round(v)))" }
            return ExactMathValueFormatter.format(v, preferFraction: preferFraction)
        case .symbolicConst(let sym, _):
            return sym
        case .varX: return "x"
        case .varY: return "y"
        case .varZ: return "z"
        case .neg(let a):
            let s = format(a, preferFraction: preferFraction)
            if case .add = a { return "-(\(s))" }
            if case .sub = a { return "-(\(s))" }
            return "-\(s)"
        case .add(let a, let b):
            let sb = format(b, preferFraction: preferFraction)
            if sb.hasPrefix("-") { return "\(format(a, preferFraction: preferFraction)) - \(sb.dropFirst())" }
            return "\(format(a, preferFraction: preferFraction)) + \(sb)"
        case .sub(let a, let b):
            return "\(format(a, preferFraction: preferFraction)) - \(format(b, preferFraction: preferFraction))"
        case .mul(let a, let b):
            let sa = formatFactor(a, preferFraction: preferFraction)
            let sb = formatFactor(b, preferFraction: preferFraction)
            if case .number(let va) = a {
                if abs(va - 1.0) < 1e-9 { return sb }
                if abs(va + 1.0) < 1e-9 { return "-\(sb)" }
            }
            return "\(sa)·\(sb)"
        case .div(let a, let b):
            // 若是纯数字分数 (如 3/4)，直接输出 "3/4"，不加多余括号
            if case .number(let va) = a, case .number(let vb) = b,
               abs(va - round(va)) < 1e-9, abs(vb - round(vb)) < 1e-9 {
                return "\(Int(round(va)))/\(Int(round(vb)))"
            }
            let sa = formatFactor(a, preferFraction: preferFraction)
            let sb = formatFactor(b, preferFraction: preferFraction)
            return "\(sa)/\(sb)"
        case .pow(let a, let b):
            let sa = formatFactor(a, preferFraction: preferFraction)
            if case .number(let vb) = b {
                if abs(vb - 2.0) < 1e-9 { return "\(sa)²" }
                if abs(vb - 3.0) < 1e-9 { return "\(sa)³" }
                if abs(vb - 4.0) < 1e-9 { return "\(sa)⁴" }
            }
            return "\(sa)^(\(format(b, preferFraction: preferFraction)))"
        case .call(let fn, let a):
            if fn == "sqrt" { return "√(\(format(a, preferFraction: preferFraction)))" }
            if fn == "abs"  { return "|\(format(a, preferFraction: preferFraction))|" }
            return "\(fn)(\(format(a, preferFraction: preferFraction)))"
        }
    }

    private static func formatFactor(_ node: MathAST, preferFraction: Bool) -> String {
        switch node {
        case .add, .sub, .div: return "(\(format(node, preferFraction: preferFraction)))"
        default: return format(node, preferFraction: preferFraction)
        }
    }
}

// MARK: - 7. 自然数学排版美化器与带字节码缓存的多元编译器 (保留分数斜杠 3/4)

enum NaturalMathFormatter {
    static func prettifyForDisplay(_ raw: String) -> String {
        if raw.isEmpty { return "0" }
        return raw
            .replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "^2", with: "²")
            .replacingOccurrences(of: "^3", with: "³")
            .replacingOccurrences(of: "^4", with: "⁴")
            .replacingOccurrences(of: "^(-1)", with: "⁻¹")
            .replacingOccurrences(of: "sqrt(", with: "√(")
            .replacingOccurrences(of: "asin(", with: "sin⁻¹(")
            .replacingOccurrences(of: "acos(", with: "cos⁻¹(")
            .replacingOccurrences(of: "atan(", with: "tan⁻¹(")
            .replacingOccurrences(of: "*", with: "·")
    }

    static func autoBalanceParentheses(_ raw: String) -> String {
        var openCount = 0
        for ch in raw {
            if ch == "(" { openCount += 1 }
            else if ch == ")" && openCount > 0 { openCount -= 1 }
        }
        if openCount > 0 {
            return raw + String(repeating: ")", count: openCount)
        }
        return raw
    }

    @inline(__always)
    static func cleanZero(_ v: Double) -> Double {
        return abs(v) < 1e-9 ? 0.0 : v
    }
}

final class MultivariateMathParser {
    enum Token {
        case number(Double)
        case symbolicConst(String, Double)
        case variableX
        case variableY
        case variableZ
        case op(Character)
        case function(String)
        case leftParen
        case rightParen
    }

    private static var rpnCache: [String: [RPNInstruction]] = [:]

    private static func isDigit(_ c: Character) -> Bool {
        return (c >= "0" && c <= "9")
    }

    private static func isAlpha(_ c: Character) -> Bool {
        return (c >= "a" && c <= "z") || (c >= "A" && c <= "Z")
    }

    static func normalizeEquationToZeroForm(_ expression: String) -> (isEquation: Bool, normalized: String, rhsValue: Double) {
        let balanced = NaturalMathFormatter.autoBalanceParentheses(expression)
        if balanced.contains("=") {
            let parts = balanced.components(separatedBy: "=")
            if parts.count == 2 && !parts[0].isEmpty && !parts[1].isEmpty {
                let lhs = parts[0]
                let rhs = parts[1]
                let rhsVal = Double(rhs) ?? 1.0
                return (true, "(\(lhs))-(\(rhs))", rhsVal)
            }
        }
        return (false, balanced, 0.0)
    }

    static func tokenize(_ input: String) -> [Token] {
        let (_, normalizedInput, _) = normalizeEquationToZeroForm(input)
        let s = normalizedInput
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "·", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "−", with: "-")
            .replacingOccurrences(of: "⁻¹", with: "^(-1)")
            .replacingOccurrences(of: "²", with: "^2")
            .replacingOccurrences(of: "³", with: "^3")
            .replacingOccurrences(of: "⁴", with: "^4")
            .replacingOccurrences(of: "√(", with: "sqrt(")

        var rawTokens: [Token] = []
        let chars = Array(s)
        var i = 0

        while i < chars.count {
            let c = chars[i]
            if isDigit(c) || c == "." {
                var numStr = String(c)
                i += 1
                while i < chars.count && (isDigit(chars[i]) || chars[i] == ".") {
                    numStr.append(chars[i])
                    i += 1
                }
                if let val = Double(numStr) {
                    rawTokens.append(.number(val))
                }
            } else if c == "π" {
                rawTokens.append(.symbolicConst("π", Double.pi))
                i += 1
            } else if c == "x" || c == "X" || c == "θ" {
                rawTokens.append(.variableX)
                i += 1
            } else if c == "y" || c == "Y" || c == "φ" {
                rawTokens.append(.variableY)
                i += 1
            } else if c == "z" || c == "Z" {
                rawTokens.append(.variableZ)
                i += 1
            } else if c == "e" && (i + 1 >= chars.count || !isAlpha(chars[i + 1])) {
                rawTokens.append(.symbolicConst("e", M_E))
                i += 1
            } else if isAlpha(c) {
                var fn = String(c)
                i += 1
                while i < chars.count && isAlpha(chars[i]) {
                    fn.append(chars[i])
                    i += 1
                }
                rawTokens.append(.function(fn.lowercased()))
            } else if c == "(" {
                rawTokens.append(.leftParen)
                i += 1
            } else if c == ")" {
                rawTokens.append(.rightParen)
                i += 1
            } else if "+-*/^".contains(c) {
                rawTokens.append(.op(c))
                i += 1
            } else {
                i += 1
            }
        }

        var tokens: [Token] = []
        tokens.reserveCapacity(rawTokens.count * 2)
        for idx in 0..<rawTokens.count {
            let current = rawTokens[idx]
            tokens.append(current)
            if idx + 1 < rawTokens.count {
                let next = rawTokens[idx + 1]
                if needsImplicitMultiply(left: current, right: next) {
                    tokens.append(.op("*"))
                }
            }
        }
        return tokens
    }

    private static func needsImplicitMultiply(left: Token, right: Token) -> Bool {
        let leftIsValue: Bool
        switch left {
        case .number, .symbolicConst, .variableX, .variableY, .variableZ, .rightParen:
            leftIsValue = true
        default:
            leftIsValue = false
        }

        let rightIsFactor: Bool
        switch right {
        case .variableX, .variableY, .variableZ, .symbolicConst, .function, .leftParen, .number:
            if case .number = left, case .number = right {
                rightIsFactor = false
            } else {
                rightIsFactor = true
            }
        default:
            rightIsFactor = false
        }
        return leftIsValue && rightIsFactor
    }

    static func parseAST(_ expression: String) -> MathAST {
        let tokens = tokenize(expression)
        guard !tokens.isEmpty else { return .number(0) }
        var pos = 0

        func parseExpr() -> MathAST {
            var node = parseTerm()
            while pos < tokens.count {
                if case .op(let op) = tokens[pos], op == "+" || op == "-" {
                    pos += 1
                    let rhs = parseTerm()
                    node = (op == "+") ? .add(node, rhs) : .sub(node, rhs)
                } else {
                    break
                }
            }
            return node
        }

        func parseTerm() -> MathAST {
            var node = parsePower()
            while pos < tokens.count {
                if case .op(let op) = tokens[pos], op == "*" || op == "/" {
                    pos += 1
                    let rhs = parsePower()
                    node = (op == "*") ? .mul(node, rhs) : .div(node, rhs)
                } else {
                    break
                }
            }
            return node
        }

        func parsePower() -> MathAST {
            let base = parseUnary()
            if pos < tokens.count, case .op("^") = tokens[pos] {
                pos += 1
                let expNode = parsePower()
                return .pow(base, expNode)
            }
            return base
        }

        func parseUnary() -> MathAST {
            if pos < tokens.count, case .op(let op) = tokens[pos] {
                if op == "-" {
                    pos += 1
                    return .neg(parseUnary())
                } else if op == "+" {
                    pos += 1
                    return parseUnary()
                }
            }
            return parsePrimary()
        }

        func parsePrimary() -> MathAST {
            guard pos < tokens.count else { return .number(0) }
            let token = tokens[pos]
            pos += 1

            switch token {
            case .number(let v): return .number(v)
            case .symbolicConst(let s, let v): return .symbolicConst(s, v)
            case .variableX: return .varX
            case .variableY: return .varY
            case .variableZ: return .varZ
            case .leftParen:
                let inside = parseExpr()
                if pos < tokens.count, case .rightParen = tokens[pos] { pos += 1 }
                return inside
            case .function(let fn):
                if pos < tokens.count, case .leftParen = tokens[pos] { pos += 1 }
                let arg = parseExpr()
                if pos < tokens.count, case .rightParen = tokens[pos] { pos += 1 }
                return .call(fn, arg)
            default:
                return .number(0)
            }
        }

        return SymbolicCalculusEngine.simplify(parseExpr())
    }

    private static func getCompiledRPN(_ expression: String) -> [RPNInstruction] {
        if let cached = rpnCache[expression] {
            return cached
        }
        let ast = parseAST(expression)
        var rpn: [RPNInstruction] = []
        SymbolicCalculusEngine.compileToRPN(ast, into: &rpn)
        if rpnCache.count > 64 { rpnCache.removeAll() }
        rpnCache[expression] = rpn
        return rpn
    }

    static func compileRaw3D(_ expression: String) -> (Double, Double, Double) -> Double {
        let rpn = getCompiledRPN(expression)
        return { x, y, z in
            return SymbolicCalculusEngine.evalRPN(rpn, x: x, y: y, z: z)
        }
    }

    static func compileSafe3D(_ expression: String) -> (Double, Double, Double) -> Double {
        let rpn = getCompiledRPN(expression)
        return { x, y, z in
            let v = SymbolicCalculusEngine.evalRPN(rpn, x: x, y: y, z: z)
            return (v.isFinite && abs(v) < 50000.0) ? v : 0.0
        }
    }
}

// MARK: - 8. 考场第一眼破题直觉与避坑教练引擎

struct ExamProblemPreset {
    let title: String
    let subtitle: String
    let pageType: IntegralPageType
    let coordMode: CoordinateSystemMode
    let expression: String
    let xMin: String
    let xMax: String
    let yMin: String
    let yMax: String
    let zMin: String
    let zMax: String
    let keyTakeaway: String
}

final class ExamIntuitionCoachEngine {

    static let classicExamProblems: [ExamProblemPreset] = [
        ExamProblemPreset(
            title: "①【奇偶性秒杀题】∫[-2,2] x³·cos(x) dx",
            subtitle: "考场看到对称区间 [-a, a]，第一件事永远是先验奇偶性！",
            pageType: .singleIntegral,
            coordMode: .cartesian,
            expression: "x^3*cos(x)",
            xMin: "-2", xMax: "2", yMin: "-2", yMax: "2", zMin: "-1", zMax: "1",
            keyTakeaway: "f(-x) = (-x)³cos(-x) = -f(x) 为奇函数，在 [-2,2] 上正负面积抵消，考场直接写 = 0！"
        ),
        ExamProblemPreset(
            title: "②【分部积分·幂×指】∫[0,1] x·exp(x) dx",
            subtitle: "口诀「反对幂指三」：幂函数 x 在指数 eˣ 前面，故令 u = x",
            pageType: .singleIntegral,
            coordMode: .cartesian,
            expression: "x*exp(x)",
            xMin: "0", xMax: "1", yMin: "-1", yMax: "1", zMin: "-1", zMax: "1",
            keyTakeaway: "令 u=x, dv=eˣdx ⇒ 原函数 (x-1)eˣ，代入 [0,1] 得 0 - (-1) = 1。"
        ),
        ExamProblemPreset(
            title: "③【分部积分·单对数】∫[1,e] ln(x) dx",
            subtitle: "单个 ln(x) 怎么积？直接把 1·dx 看作 dv，用分部积分！",
            pageType: .singleIntegral,
            coordMode: .cartesian,
            expression: "ln(x)",
            xMin: "1", xMax: "e", yMin: "-1", yMax: "1", zMin: "-1", zMax: "1",
            keyTakeaway: "∫ln(x)dx = x·ln(x) - ∫x·(1/x)dx = x·ln(x) - x，代入 [1, e] 得 1。"
        ),
        ExamProblemPreset(
            title: "④【分部积分·幂×三角】∫[0,π] x·sin(x) dx",
            subtitle: "幂函数×三角函数：令 u = x 降次，注意 ∫sin(x)dx = -cos(x) 的负号！",
            pageType: .singleIntegral,
            coordMode: .cartesian,
            expression: "x*sin(x)",
            xMin: "0", xMax: "π", yMin: "-1", yMax: "1", zMin: "-1", zMax: "1",
            keyTakeaway: "原函数为 sin(x) - x·cos(x)，代入 [0, π] 得 π。"
        ),
        ExamProblemPreset(
            title: "⑤【旋转体微元必考】y = √x 在 [0,2] 绕 X 轴旋转",
            subtitle: "3D 重压看图并拖动底部【微元切片 x₀】，亲眼看薄圆盘 π·f(x)²dx 如何积成旋转体！",
            pageType: .singleIntegral,
            coordMode: .cartesian,
            expression: "√(x)",
            xMin: "0", xMax: "2", yMin: "-2", yMax: "2", zMin: "-1", zMax: "1",
            keyTakeaway: "旋转体体积公式 V = π∫[0,2] (√x)² dx = π·[x²/2]₀² = 2π。"
        ),
        ExamProblemPreset(
            title: "⑥【二重积分·极坐标母题】∬ exp(-(x²+y²)) dxdy",
            subtitle: "看到 x²+y² 千万别在直角坐标硬算！换极坐标多出雅可比因子 r 瞬间凑微分！",
            pageType: .doubleIntegral,
            coordMode: .cartesian,
            expression: "exp(-(x^2+y^2))",
            xMin: "-2", xMax: "2", yMin: "-2", yMax: "2", zMin: "-1", zMax: "1",
            keyTakeaway: "换极坐标后变为 ∫dθ ∫ e^(-r²)·r dr = ∫ (-1/2)e^(-r²) d(r²)，千万别漏乘 r！"
        ),
        ExamProblemPreset(
            title: "⑦【多元偏导与切平面】z = sin(x)·cos(y)",
            subtitle: "求 ∂f/∂x 时把 y 当常数，求 ∂f/∂y 时把 x 当常数！",
            pageType: .doubleIntegral,
            coordMode: .cartesian,
            expression: "sin(x)*cos(y)",
            xMin: "-π", xMax: "π", yMin: "-π", yMax: "π", zMin: "-1", zMax: "1",
            keyTakeaway: "切平面方程：z - z₀ = fx(x₀,y₀)(x - x₀) + fy(x₀,y₀)(y - y₀)，3D 视图可直接看切面！"
        ),
        ExamProblemPreset(
            title: "⑧【空间球面与三重积分】x²+y²+z² = 1",
            subtitle: "隐式球面方程：直观观察半径 R=1 的球体、体积 4π/3 与表面积 4π",
            pageType: .tripleIntegral,
            coordMode: .implicitSurface,
            expression: "x^2+y^2+z^2=1",
            xMin: "-1", xMax: "1", yMin: "-1", yMax: "1", zMin: "-1", zMax: "1",
            keyTakeaway: "球体积 V = 4π/3，球表面积 S = 4π。"
        )
    ]

    static func diagnoseProblem(
        params: CalculusInputParameters,
        fRaw: (Double, Double, Double) -> Double,
        isImplicitEq: Bool
    ) -> (oneLineHint: String, intuitionGuide: String, trapWarning: String) {
        let expr = params.expression.lowercased()
        let a = params.xMin
        let b = params.xMax

        if isImplicitEq || params.coordMode == .implicitSurface {
            return (
                "💡 隐式曲面 F(x,y,z)=C · 重压看 3D 球体/等值面",
                "【破题直觉】方程含“=”，属隐式曲面 F(x,y,z)=0。法向量 n = (Fx, Fy, Fz)，隐函数偏导 ∂z/∂x = −Fx/Fz。",
                "【⚠️ 避坑提示】隐函数求导公式 ∂z/∂x = −Fx/Fz 切勿漏掉前面的负号“−”！"
            )
        }

        if params.pageType == .singleIntegral && abs(a + b) < 1e-4 && abs(b - a) > 1e-4 {
            let testPts = [0.23 * b, 0.51 * b, 0.83 * b]
            var isOdd = true
            var isEven = true
            for tx in testPts {
                let fp = fRaw(tx, 0, 0)
                let fn = fRaw(-tx, 0, 0)
                if !fp.isFinite || !fn.isFinite { isOdd = false; isEven = false; break }
                if abs(fp + fn) > 1e-4 * (1.0 + abs(fp)) { isOdd = false }
                if abs(fp - fn) > 1e-4 * (1.0 + abs(fp)) { isEven = false }
            }
            if isOdd {
                return (
                    "💡 对称区间奇函数：正负面积抵消，考场直接写 = 0",
                    "【破题直觉：对称区间 + 奇函数秒杀】上下限关于原点对称且 f(−x) = −f(x) 为奇函数，正负面积完全抵消，考场直接写 = 0 拿满分！",
                    "【⚠️ 避坑提示】凡是上下限形如 [-a, a]，切忌直接硬算原函数，永远先花 2 秒判断奇偶性（偶倍奇零）。"
                )
            } else if isEven {
                return (
                    "💡 对称区间偶函数：可化为 2·∫[0, a] f(x)dx",
                    "【破题直觉：对称区间 + 偶函数折半】f(−x) = f(x) 为偶函数，先写：原式 = 2·∫[0, \(ExactMathValueFormatter.format(abs(b), preferFraction: params.preferFraction))] f(x)dx。",
                    "【⚠️ 避坑提示】折半后下限变为 0，但注意 cos(0)=1、e⁰=1（不等于 0），代入下限时切勿漏减！"
                )
            }
        }

        if params.pageType == .doubleIntegral && (expr.contains("x^2+y^2") || expr.contains("x²+y²")) {
            return (
                "💡 含 x²+y² 特征：考场必换【极坐标】dxdy = r·dr·dθ",
                "【破题直觉：极坐标换元】令 x=r·cosθ, y=r·sinθ，将 x²+y² 换为 r²，面积微元换为 dxdy = r·dr·dθ。",
                "【⚠️ 避坑提示】换极坐标时千万别漏乘雅可比因子【r】！"
            )
        }

        let hasLog = expr.contains("ln")
        let hasArc = expr.contains("asin") || expr.contains("acos") || expr.contains("atan")
        let hasTrig = expr.contains("sin") || expr.contains("cos")
        let hasExp = expr.contains("exp") || expr.contains("e^")
        let hasX = expr.contains("x")

        if params.pageType == .singleIntegral && (hasLog || hasArc || (hasX && (hasTrig || hasExp))) {
            return (
                "💡 口诀【反对幂指三】：用分部积分 ∫u·dv = u·v − ∫v·du",
                "【破题直觉：分部积分“反对幂指三”】按【反三角 → 对数ln → 幂xⁿ → 指数eˣ → 三角sin/cos】顺序，排前面的设 u 求导，排后面的凑入 dv。",
                "【⚠️ 避坑提示】分部积分公式 u·v − ∫v·du 中间是减号，且定积分第一项 [u·v]ₐᵇ 也要代入上下限！"
            )
        }

        switch params.pageType {
        case .singleIntegral:
            return (
                "💡 定积分：重压黑屏看 2D 正负面积与 3D 旋转体微元",
                "【破题直觉】先看能否直接套基本公式或凑微分；重压上方黑屏可看 2D 正负面积与 3D 旋转体黄金圆盘微元。",
                "【⚠️ 避坑提示】定积分换元时记住“换元必换限”，算完 dt 立即同步更换上下限！"
            )
        case .doubleIntegral:
            return (
                "💡 二重积分：先积谁就把另一变量当常数",
                "【破题直觉】求 ∂f/∂x 时把 y 当常数；若内层积不出初等原函数，考场必考【交换积分次序】或【极坐标】。",
                "【⚠️ 避坑提示】交换积分次序时不能直接对调上下限，必须先画区域草图重新穿线定限。"
            )
        case .tripleIntegral:
            return (
                "💡 三重积分：穿线法(先一后二) / 柱坐标 / 球坐标",
                "【破题直觉】含 x²+y² 用柱坐标 r·drdθdz；含 x²+y²+z² 用球坐标 r²sinφ·drdφdθ。",
                "【⚠️ 避坑提示】球坐标雅可比因子是 r²·sinφ，且 φ 的范围是 [0, π] 而非 [0, 2π]。"
            )
        }
    }
}

// MARK: - 9. 数值微积分与综合分析器 (遵循分数 vs 小数一致性)

final class LeastSquaresFitEngine {
    static func fitExperimentalPoints(_ points: [(Double, Double)]) -> (equation: String, report: String) {
        let n = Double(points.count)
        guard points.count >= 2 else { return ("x", "数据点不足") }
        var sumX = 0.0, sumY = 0.0, sumXY = 0.0, sumX2 = 0.0
        for (x, y) in points {
            sumX += x; sumY += y; sumXY += x * y; sumX2 += x * x
        }
        let denom = n * sumX2 - sumX * sumX
        let slope = abs(denom) > 1e-12 ? (n * sumXY - sumX * sumY) / denom : 0.0
        let intercept = (sumY - slope * sumX) / n

        let meanY = sumY / n
        var ssTot = 0.0, ssRes = 0.0
        for (x, y) in points {
            let pred = slope * x + intercept
            ssRes += (y - pred) * (y - pred)
            ssTot += (y - meanY) * (y - meanY)
        }
        let r2 = ssTot > 1e-12 ? max(0.0, 1.0 - ssRes / ssTot) : 1.0
        let rmse = sqrt(ssRes / n)

        let eq = String(format: "%.3f*x%+.3f", slope, intercept)
        let rep = String(format: "最小二乘回归: y = %.3fx %+.3f  (R² = %.4f, RMSE = %.4f)", slope, intercept, r2, rmse)
        return (eq, rep)
    }
}

enum IntegralPageType: Int {
    case singleIntegral = 0
    case doubleIntegral = 1
    case tripleIntegral = 2
}

enum CoordinateSystemMode: Int {
    case cartesian = 0
    case polarOrSpherical = 1
    case implicitSurface = 2
}

enum OnDemandDisplayCategory: Int {
    case primaryOnly = 0
    case derivAndGeometry = 1
    case scoringSteps = 2
    case limitAndTangent = 3
    case trapsAndFit = 4
}

struct CalculusInputParameters {
    var pageType: IntegralPageType
    var coordMode: CoordinateSystemMode
    var expression: String
    var xMin: Double
    var xMax: Double
    var yMin: Double
    var yMax: Double
    var zMin: Double
    var zMax: Double
    var x0: Double
    var y0: Double
    var preferFraction: Bool
}

struct FullCalculusAnalysis {
    let primaryIntegralResultText: String
    let oneLineCoachHint: String
    let examIntuitionText: String
    let scoringStepsText: String
    let derivDetailText: String
    let limitAndTangentText: String
    let trapAndFitText: String
    let pureFitText: String
    let summaryBanner: String
    let z0: Double
    let fx: Double
    let fy: Double
    let isImplicitEquation: Bool
}

final class NumericalCalculusEngine {

    static func isDiscontinuousSegment(v1: Double, v2: Double, jumpLimit: Double = 12.0) -> Bool {
        if !v1.isFinite || !v2.isFinite { return true }
        if abs(v1) > 35.0 || abs(v2) > 35.0 { return true }
        if (v1 * v2 < 0) && abs(v2 - v1) > jumpLimit * 0.40 { return true }
        if abs(v2 - v1) > jumpLimit { return true }
        return false
    }

    static func evaluateLimitWrtX(
        _ fRaw: (Double, Double, Double) -> Double,
        x0: Double,
        y0: Double,
        preferFraction: Bool
    ) -> String {
        let left1 = fRaw(x0 - 1e-3, y0, 0)
        let left2 = fRaw(x0 - 1e-5, y0, 0)
        let right2 = fRaw(x0 + 1e-5, y0, 0)
        let x0Str = ExactMathValueFormatter.format(x0, preferFraction: preferFraction)

        if !left2.isFinite || !right2.isFinite || abs(left2) > 1e3 || abs(right2) > 1e3 {
            let lSign = left2 > 0 ? "+∞" : "-∞"
            let rSign = right2 > 0 ? "+∞" : "-∞"
            return "x→\(x0Str): 奇点(\(lSign)/\(rSign))"
        }
        if abs(left2 - right2) > max(1e-2, 0.05 * (abs(left2) + abs(right2))) && abs(left2 - left1) < abs(left2 - right2) {
            return String(format: "x→%@: 跳跃间断(左=%.2f≠右=%.2f)", x0Str, left2, right2)
        }
        let limVal = NaturalMathFormatter.cleanZero(0.5 * (left2 + right2))
        let limStr = ExactMathValueFormatter.format(limVal, preferFraction: preferFraction)
        return "lim(x→\(x0Str)) = \(limStr) (连续)"
    }

    static func partialDerivativeX(
        _ f: (Double, Double, Double) -> Double,
        x0: Double, y0: Double, z0: Double = 0.0, h: Double = 1e-4
    ) -> Double {
        let val = (f(x0 - 2 * h, y0, z0) - 8 * f(x0 - h, y0, z0) + 8 * f(x0 + h, y0, z0) - f(x0 + 2 * h, y0, z0)) / (12.0 * h)
        if !val.isFinite { return 0.0 }
        return NaturalMathFormatter.cleanZero(max(-250.0, min(250.0, val)))
    }

    static func partialDerivativeY(
        _ f: (Double, Double, Double) -> Double,
        x0: Double, y0: Double, z0: Double = 0.0, h: Double = 1e-4
    ) -> Double {
        let val = (f(x0, y0 - 2 * h, z0) - 8 * f(x0, y0 - h, z0) + 8 * f(x0, y0 + h, z0) - f(x0, y0 + 2 * h, z0)) / (12.0 * h)
        if !val.isFinite { return 0.0 }
        return NaturalMathFormatter.cleanZero(max(-250.0, min(250.0, val)))
    }

    static func partialDerivativeZ(
        _ f: (Double, Double, Double) -> Double,
        x0: Double, y0: Double, z0: Double, h: Double = 1e-4
    ) -> Double {
        let val = (f(x0, y0, z0 - 2 * h) - 8 * f(x0, y0, z0 - h) + 8 * f(x0, y0, z0 + h) - f(x0, y0, z0 + 2 * h)) / (12.0 * h)
        if !val.isFinite { return 0.0 }
        return NaturalMathFormatter.cleanZero(max(-250.0, min(250.0, val)))
    }

    static func integrate1D(_ g: (Double) -> Double, a: Double, b: Double, steps: Int = 180) -> Double {
        let n = (steps % 2 == 0) ? steps : steps + 1
        let h = (b - a) / Double(n)
        guard abs(h) > 1e-12 else { return 0.0 }
        var sum = g(a) + g(b)
        for i in 1..<n {
            let x = a + Double(i) * h
            let weight = (i % 2 == 1) ? 4.0 : 2.0
            sum += weight * g(x)
        }
        return NaturalMathFormatter.cleanZero(sum * (h / 3.0))
    }

    static func integrate2DSimpson(
        _ f: (Double, Double, Double) -> Double,
        xMin: Double, xMax: Double, yMin: Double, yMax: Double,
        nx: Int = 44, ny: Int = 44
    ) -> Double {
        let evenNx = (nx % 2 == 0) ? nx : nx + 1
        let evenNy = (ny % 2 == 0) ? ny : ny + 1
        let hx = (xMax - xMin) / Double(evenNx)
        let hy = (yMax - yMin) / Double(evenNy)
        guard abs(hx) > 1e-12, abs(hy) > 1e-12 else { return 0.0 }

        var total = 0.0
        for i in 0...evenNx {
            let x = xMin + Double(i) * hx
            let wx: Double = (i == 0 || i == evenNx) ? 1.0 : ((i % 2 == 1) ? 4.0 : 2.0)
            var innerSum = 0.0
            for j in 0...evenNy {
                let y = yMin + Double(j) * hy
                let wy: Double = (j == 0 || j == evenNy) ? 1.0 : ((j % 2 == 1) ? 4.0 : 2.0)
                innerSum += wy * f(x, y, 0.0)
            }
            total += wx * innerSum
        }
        return NaturalMathFormatter.cleanZero(total * (hx * hy) / 9.0)
    }

    static func integrate3DSimpson(
        _ f: (Double, Double, Double) -> Double,
        xMin: Double, xMax: Double, yMin: Double, yMax: Double, zMin: Double, zMax: Double,
        nGrid: Int = 18
    ) -> Double {
        let n = (nGrid % 2 == 0) ? nGrid : nGrid + 1
        let hx = (xMax - xMin) / Double(n)
        let hy = (yMax - yMin) / Double(n)
        let hz = (zMax - zMin) / Double(n)
        guard abs(hx) > 1e-12, abs(hy) > 1e-12, abs(hz) > 1e-12 else { return 0.0 }

        var total = 0.0
        for i in 0...n {
            let x = xMin + Double(i) * hx
            let wx: Double = (i == 0 || i == n) ? 1.0 : ((i % 2 == 1) ? 4.0 : 2.0)
            var sumY = 0.0
            for j in 0...n {
                let y = yMin + Double(j) * hy
                let wy: Double = (j == 0 || j == n) ? 1.0 : ((j % 2 == 1) ? 4.0 : 2.0)
                var sumZ = 0.0
                for k in 0...n {
                    let z = zMin + Double(k) * hz
                    let wz: Double = (k == 0 || k == n) ? 1.0 : ((k % 2 == 1) ? 4.0 : 2.0)
                    sumZ += wz * f(x, y, z)
                }
                sumY += wy * sumZ
            }
            total += wx * sumY
        }
        return NaturalMathFormatter.cleanZero(total * (hx * hy * hz) / 27.0)
    }

    static func analyze(params: CalculusInputParameters) -> FullCalculusAnalysis {
        let (isEq, _, rhsVal) = MultivariateMathParser.normalizeEquationToZeroForm(params.expression)
        let ast = MultivariateMathParser.parseAST(params.expression)
        let fRaw = MultivariateMathParser.compileRaw3D(params.expression)
        let fSafe = MultivariateMathParser.compileSafe3D(params.expression)
        let pf = params.preferFraction

        let dfxAST = SymbolicCalculusEngine.simplify(SymbolicCalculusEngine.differentiate(ast, wrt: "x"))
        let dfyAST = SymbolicCalculusEngine.simplify(SymbolicCalculusEngine.differentiate(ast, wrt: "y"))
        let dfzAST = SymbolicCalculusEngine.simplify(SymbolicCalculusEngine.differentiate(ast, wrt: "z"))

        let symFx = NaturalMathFormatter.prettifyForDisplay(SymbolicCalculusEngine.format(dfxAST, preferFraction: pf))
        let symFy = NaturalMathFormatter.prettifyForDisplay(SymbolicCalculusEngine.format(dfyAST, preferFraction: pf))
        let symFz = NaturalMathFormatter.prettifyForDisplay(SymbolicCalculusEngine.format(dfzAST, preferFraction: pf))

        let z0 = NaturalMathFormatter.cleanZero(max(-200.0, min(200.0, fSafe(params.x0, params.y0, 0.0))))
        let fx = partialDerivativeX(fSafe, x0: params.x0, y0: params.y0)
        let fy = partialDerivativeY(fSafe, x0: params.x0, y0: params.y0)

        let samplePts: [(Double, Double)] = [
            (1.0, 2.05), (2.0, 3.92), (3.0, 6.10), (4.0, 7.95), (5.0, 10.08)
        ]
        let (_, fitRep) = LeastSquaresFitEngine.fitExperimentalPoints(samplePts)
        let (oneLineHint, intuitionGuide, trapWarning) = ExamIntuitionCoachEngine.diagnoseProblem(
            params: params, fRaw: fRaw, isImplicitEq: isEq
        )

        // 隐式球面或曲面方程（如 x²+y²+z²=100）：精确计算球/椭球半轴并格式化为 4000π/3 与 400π
        if isEq || params.coordMode == .implicitSurface {
            let (rx, ry, rz) = Surface3DBuilder.extractEllipsoidRadii(expression: params.expression, fallbackRhs: rhsVal)
            let ellipVol = (4.0 / 3.0) * Double.pi * rx * ry * rz
            let rMean = (rx + ry + rz) / 3.0
            let sphereArea = 4.0 * Double.pi * rMean * rMean

            let volFormatted = ExactMathValueFormatter.format(ellipVol, preferFraction: pf, prefix: "球体积 V = ")
            let volShort = ExactMathValueFormatter.format(ellipVol, preferFraction: pf)
            let areaShort = ExactMathValueFormatter.format(sphereArea, preferFraction: pf)
            let rStr = ExactMathValueFormatter.format(rMean, preferFraction: pf)

            return FullCalculusAnalysis(
                primaryIntegralResultText: Calculus3DOriginalityWatermark.guardOutput(volFormatted),
                oneLineCoachHint: oneLineHint,
                examIntuitionText: intuitionGuide,
                scoringStepsText: "① 识别球/曲面半径 R = \(rStr)\n② 球体积 V = (4/3)πR³ = \(volShort)  |  表面积 S = 4πR² = \(areaShort)",
                derivDetailText: "隐函数梯度 ∇F = (\(symFx), \(symFy), \(symFz))\n隐函数偏导 ∂z/∂x = −(\(symFx))/(\(symFz))",
                limitAndTangentText: "球/曲面半径 R = \(rStr)  |  表面积 S = \(areaShort)",
                trapAndFitText: "\(trapWarning)\n\(fitRep)",
                pureFitText: fitRep,
                summaryBanner: "隐式 3D 球/曲面  |  体积 V = \(volShort)  |  表面积 S = \(areaShort)",
                z0: z0,
                fx: fx,
                fy: fy,
                isImplicitEquation: true
            )
        }

        switch params.pageType {
        case .singleIntegral:
            let int1D = integrate1D({ x in fSafe(x, 0, 0) }, a: params.xMin, b: params.xMax)
            let aOrdered = min(params.xMin, params.xMax)
            let bOrdered = max(params.xMin, params.xMax)
            let revVol = Double.pi * integrate1D({ x in
                let yv = max(-250.0, min(250.0, fSafe(x, 0, 0)))
                return yv * yv
            }, a: aOrdered, b: bOrdered)
            let arcLen = integrate1D({ x in
                let d = partialDerivativeX(fSafe, x0: x, y0: 0)
                return sqrt(1.0 + d * d)
            }, a: aOrdered, b: bOrdered)
            let limDesc = evaluateLimitWrtX(fRaw, x0: params.x0, y0: 0, preferFraction: pf)
            let (_, stepsText) = SymbolicCalculusEngine.integrateSymbolicWithStepsWrtX(
                ast, a: params.xMin, b: params.xMax, numResult: int1D, preferFraction: pf
            )

            let primaryStr = ExactMathValueFormatter.format(int1D, preferFraction: pf, prefix: "= ")
            let revVolStr = ExactMathValueFormatter.format(revVol, preferFraction: pf)
            let arcLenStr = ExactMathValueFormatter.format(arcLen, preferFraction: pf)
            let x0Str = ExactMathValueFormatter.format(params.x0, preferFraction: pf)
            let fxStr = ExactMathValueFormatter.format(fx, preferFraction: pf)

            return FullCalculusAnalysis(
                primaryIntegralResultText: Calculus3DOriginalityWatermark.guardOutput(primaryStr),
                oneLineCoachHint: oneLineHint,
                examIntuitionText: intuitionGuide,
                scoringStepsText: stepsText,
                derivDetailText: "一阶导数 f'(x) = \(symFx)\n在 x₀=\(x0Str) 处切线斜率 f'(x₀) = \(fxStr)",
                limitAndTangentText: "旋转体体积 V = \(revVolStr)  |  弧长 L = \(arcLenStr)\n\(limDesc)",
                trapAndFitText: "\(trapWarning)\n\(fitRep)",
                pureFitText: fitRep,
                summaryBanner: "定积分 \(primaryStr)  |  旋转体 V = \(revVolStr)",
                z0: z0,
                fx: fx,
                fy: 0.0,
                isImplicitEquation: false
            )

        case .doubleIntegral:
            let int2D = integrate2DSimpson(fSafe, xMin: params.xMin, xMax: params.xMax, yMin: params.yMin, yMax: params.yMax)
            let area = abs((params.xMax - params.xMin) * (params.yMax - params.yMin))
            let meanVal = NaturalMathFormatter.cleanZero(area > 1e-9 ? (int2D / area) : 0.0)
            let gradNorm = NaturalMathFormatter.cleanZero(sqrt(fx * fx + fy * fy))
            let (_, stepsText) = SymbolicCalculusEngine.integrateSymbolicWithStepsWrtX(
                ast, a: params.xMin, b: params.xMax, numResult: int2D, preferFraction: pf
            )

            let primaryStr = ExactMathValueFormatter.format(int2D, preferFraction: pf, prefix: "= ")
            let areaStr = ExactMathValueFormatter.format(area, preferFraction: pf)
            let meanStr = ExactMathValueFormatter.format(meanVal, preferFraction: pf)
            let gradStr = ExactMathValueFormatter.format(gradNorm, preferFraction: pf)

            return FullCalculusAnalysis(
                primaryIntegralResultText: Calculus3DOriginalityWatermark.guardOutput(primaryStr),
                oneLineCoachHint: oneLineHint,
                examIntuitionText: intuitionGuide,
                scoringStepsText: stepsText,
                derivDetailText: "偏导 ∂f/∂x = \(symFx)   |   ∂f/∂y = \(symFy)\n梯度模长 ||∇f|| = \(gradStr)",
                limitAndTangentText: "区域面积 A = \(areaStr)  |  积分均值 f̄ = \(meanStr)",
                trapAndFitText: "\(trapWarning)\n\(fitRep)",
                pureFitText: fitRep,
                summaryBanner: "二重积分 \(primaryStr)  |  均值 f̄ = \(meanStr)",
                z0: z0,
                fx: fx,
                fy: fy,
                isImplicitEquation: false
            )

        case .tripleIntegral:
            let int3D = integrate3DSimpson(
                fSafe,
                xMin: params.xMin, xMax: params.xMax,
                yMin: params.yMin, yMax: params.yMax,
                zMin: params.zMin, zMax: params.zMax
            )
            let vol = abs((params.xMax - params.xMin) * (params.yMax - params.yMin) * (params.zMax - params.zMin))
            let avgDensity = NaturalMathFormatter.cleanZero(vol > 1e-9 ? (int3D / vol) : 0.0)
            let xm = 0.5 * (params.xMin + params.xMax)
            let ym = 0.5 * (params.yMin + params.yMax)
            let zm = 0.5 * (params.zMin + params.zMax)
            let gx = partialDerivativeX(fSafe, x0: xm, y0: ym, z0: zm)
            let gy = partialDerivativeY(fSafe, x0: xm, y0: ym, z0: zm)
            let gz = partialDerivativeZ(fSafe, x0: xm, y0: ym, z0: zm)

            let primaryStr = ExactMathValueFormatter.format(int3D, preferFraction: pf, prefix: "= ")
            let volStr = ExactMathValueFormatter.format(vol, preferFraction: pf)
            let avgStr = ExactMathValueFormatter.format(avgDensity, preferFraction: pf)

            return FullCalculusAnalysis(
                primaryIntegralResultText: Calculus3DOriginalityWatermark.guardOutput(primaryStr),
                oneLineCoachHint: oneLineHint,
                examIntuitionText: intuitionGuide,
                scoringStepsText: "三重累次积分区域体积 V(Ω) = \(volStr)\n积分结果 I = \(ExactMathValueFormatter.format(int3D, preferFraction: pf))",
                derivDetailText: "三维梯度 ∇f = (\(symFx), \(symFy), \(symFz))\n中心点梯度 = (\(ExactMathValueFormatter.format(gx, preferFraction: pf)), \(ExactMathValueFormatter.format(gy, preferFraction: pf)), \(ExactMathValueFormatter.format(gz, preferFraction: pf)))",
                limitAndTangentText: "积分域体积 V(Ω) = \(volStr)  |  体密度均值 w̄ = \(avgStr)",
                trapAndFitText: "\(trapWarning)\n\(fitRep)",
                pureFitText: fitRep,
                summaryBanner: "三重积分 \(primaryStr)  |  体积 V(Ω) = \(volStr)",
                z0: z0,
                fx: gx,
                fy: gy,
                isImplicitEquation: false
            )
        }
    }
}

// MARK: - 10. 2D 笛卡尔定积分与极坐标曲线视图 (支持任意平移、分轴拉伸与全区域无截断显示)

final class Cartesian2DPlotView: UIView {

    var expression: String = "2x"
    var coordMode: CoordinateSystemMode = .cartesian
    var viewXMin: Double = -4.0
    var viewXMax: Double = 4.0
    var viewYMin: Double = -4.0
    var viewYMax: Double = 4.0
    var integralXMin: Double = 0.0
    var integralXMax: Double = 1.0
    var x0: Double = 1.0

    private var lastPanPoint: CGPoint = .zero
    private var initialPinchSpanX: Double = 8.0
    private var initialPinchSpanY: Double = 8.0
    private var initialPinchRatioXY: Double = 1.0
    private var activeProbeX: Double?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(red: 0.05, green: 0.05, blue: 0.06, alpha: 1.0)
        contentMode = .redraw

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        addGestureRecognizer(pan)
        addGestureRecognizer(pinch)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func applyAxisStretch(multiplier: Double) {
        let m = max(0.4, min(4.0, multiplier))
        let cx = 0.5 * (viewXMin + viewXMax)
        let cy = 0.5 * (viewYMin + viewYMax)
        let baseHalfSpan = max(3.5, abs(integralXMax - integralXMin) * 1.5)
        let halfSpan = baseHalfSpan * m
        viewXMin = cx - halfSpan
        viewXMax = cx + halfSpan
        viewYMin = cy - halfSpan
        viewYMax = cy + halfSpan
        setNeedsDisplay()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        guard let touch = touches.first, bounds.width > 10 else { return }
        let forceRatio = (touch.maximumPossibleForce > 0) ? (touch.force / touch.maximumPossibleForce) : 0
        if forceRatio >= 0.45 {
            let loc = touch.location(in: self)
            let mathX = viewXMin + Double(loc.x / bounds.width) * (viewXMax - viewXMin)
            if activeProbeX == nil {
                TactileFeedbackManager.shared.play3DTouchPeek()
            } else if let prevX = activeProbeX, abs(mathX - prevX) > (viewXMax - viewXMin) * 0.04 {
                TactileFeedbackManager.shared.playModifierTap()
            }
            activeProbeX = mathX
            x0 = mathX
            setNeedsDisplay()
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        if activeProbeX != nil {
            activeProbeX = nil
            setNeedsDisplay()
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        activeProbeX = nil
        setNeedsDisplay()
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let pt = gesture.translation(in: self)
        if gesture.state == .began { lastPanPoint = .zero }
        let deltaPx = pt.x - lastPanPoint.x
        let deltaPy = pt.y - lastPanPoint.y
        lastPanPoint = pt

        guard bounds.width > 10, bounds.height > 10 else { return }
        let spanX = viewXMax - viewXMin
        let spanY = viewYMax - viewYMin

        viewXMin -= Double(deltaPx / bounds.width) * spanX
        viewXMax -= Double(deltaPx / bounds.width) * spanX
        viewYMin += Double(deltaPy / bounds.height) * spanY
        viewYMax += Double(deltaPy / bounds.height) * spanY

        setNeedsDisplay()
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        if gesture.state == .began {
            initialPinchSpanX = viewXMax - viewXMin
            initialPinchSpanY = viewYMax - viewYMin
            if gesture.numberOfTouches >= 2 {
                let p0 = gesture.location(ofTouch: 0, in: self)
                let p1 = gesture.location(ofTouch: 1, in: self)
                let dx = abs(p1.x - p0.x)
                let dy = abs(p1.y - p0.y)
                initialPinchRatioXY = (dx + dy > 10) ? Double(dx / max(1.0, dx + dy)) : 0.5
            } else {
                initialPinchRatioXY = 0.5
            }
        }
        let scale = Double(max(0.12, min(10.0, gesture.scale)))
        let centerX = 0.5 * (viewXMin + viewXMax)
        let centerY = 0.5 * (viewYMin + viewYMax)

        // 支持水平捏合单独拉伸 X 轴、垂直捏合单独拉伸 Y 轴、斜向捏合等比缩放
        let scaleX = (initialPinchRatioXY > 0.72) ? scale : ((initialPinchRatioXY < 0.28) ? 1.0 : scale)
        let scaleY = (initialPinchRatioXY < 0.28) ? scale : ((initialPinchRatioXY > 0.72) ? 1.0 : scale)

        let newSpanX = max(0.4, min(400.0, initialPinchSpanX / scaleX))
        let newSpanY = max(0.4, min(400.0, initialPinchSpanY / scaleY))

        viewXMin = centerX - 0.5 * newSpanX
        viewXMax = centerX + 0.5 * newSpanX
        viewYMin = centerY - 0.5 * newSpanY
        viewYMax = centerY + 0.5 * newSpanY

        setNeedsDisplay()
    }

    private func toScreenPoint(x: Double, y: Double, rect: CGRect) -> CGPoint {
        let px = rect.minX + CGFloat((x - viewXMin) / max(1e-6, viewXMax - viewXMin)) * rect.width
        let py = rect.maxY - CGFloat((y - viewYMin) / max(1e-6, viewYMax - viewYMin)) * rect.height
        return CGPoint(x: px, y: py)
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(), rect.width > 20, rect.height > 20 else { return }
        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)

        let fRaw = MultivariateMathParser.compileRaw3D(expression)
        let fSafe = MultivariateMathParser.compileSafe3D(expression)

        let gridPath = UIBezierPath()
        let spanX = max(0.5, viewXMax - viewXMin)
        let spanY = max(0.5, viewYMax - viewYMin)
        let stepX = Double(Surface3DBuilder.computeNiceTickStep(forLength: Float(spanX * 0.5)))
        let stepY = Double(Surface3DBuilder.computeNiceTickStep(forLength: Float(spanY * 0.5)))

        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: UIColor(white: 0.70, alpha: 1.0)
        ]

        let originScreen = toScreenPoint(x: 0, y: 0, rect: rect)
        let clampedOriginY = max(rect.minY + 92, min(rect.maxY - 98, originScreen.y))
        let clampedOriginX = max(rect.minX + 18, min(rect.maxX - 36, originScreen.x))

        var gx = floor(viewXMin / stepX) * stepX
        while gx <= viewXMax {
            let pTop = toScreenPoint(x: gx, y: viewYMax, rect: rect)
            let pBot = toScreenPoint(x: gx, y: viewYMin, rect: rect)
            gridPath.move(to: pTop)
            gridPath.addLine(to: pBot)
            if abs(gx) > 1e-5 {
                let txt = (abs(gx - round(gx)) < 1e-5) ? "\(Int(round(gx)))" : String(format: "%.1f", gx)
                (txt as NSString).draw(at: CGPoint(x: pTop.x - 8, y: clampedOriginY + 4), withAttributes: labelAttrs)
            }
            gx += stepX
        }

        var gy = floor(viewYMin / stepY) * stepY
        while gy <= viewYMax {
            let pLeft = toScreenPoint(x: viewXMin, y: gy, rect: rect)
            let pRight = toScreenPoint(x: viewXMax, y: gy, rect: rect)
            gridPath.move(to: pLeft)
            gridPath.addLine(to: pRight)
            if abs(gy) > 1e-5 {
                let txt = (abs(gy - round(gy)) < 1e-5) ? "\(Int(round(gy)))" : String(format: "%.1f", gy)
                (txt as NSString).draw(at: CGPoint(x: clampedOriginX + 5, y: pLeft.y - 7), withAttributes: labelAttrs)
            }
            gy += stepY
        }

        UIColor(white: 0.19, alpha: 1.0).setStroke()
        gridPath.lineWidth = 0.8
        gridPath.stroke()

        // 醒目绘制正负全区域 X / Y 坐标轴与箭头
        let axisPath = UIBezierPath()
        axisPath.move(to: CGPoint(x: rect.minX, y: originScreen.y))
        axisPath.addLine(to: CGPoint(x: rect.maxX, y: originScreen.y))
        axisPath.move(to: CGPoint(x: originScreen.x, y: rect.minY))
        axisPath.addLine(to: CGPoint(x: originScreen.x, y: rect.maxY))
        UIColor(white: 0.78, alpha: 1.0).setStroke()
        axisPath.lineWidth = 1.4
        axisPath.stroke()

        ("0" as NSString).draw(at: CGPoint(x: clampedOriginX - 12, y: clampedOriginY + 3), withAttributes: labelAttrs)
        ("+X" as NSString).draw(at: CGPoint(x: rect.maxX - 24, y: clampedOriginY - 16), withAttributes: labelAttrs)
        ("−X" as NSString).draw(at: CGPoint(x: rect.minX + 6, y: clampedOriginY - 16), withAttributes: labelAttrs)
        ("+Y" as NSString).draw(at: CGPoint(x: clampedOriginX + 6, y: rect.minY + 90), withAttributes: labelAttrs)
        ("−Y" as NSString).draw(at: CGPoint(x: clampedOriginX + 6, y: rect.maxY - 102), withAttributes: labelAttrs)

        if coordMode == .polarOrSpherical {
            let polarPath = UIBezierPath()
            let tMin = min(integralXMin, integralXMax)
            let tMax = max(integralXMin, integralXMax)
            let steps = 500
            let dt = max(0.01, (tMax - tMin)) / Double(steps)
            for i in 0...steps {
                let theta = tMin + Double(i) * dt
                let r = fSafe(theta, 0, 0)
                let px = r * cos(theta)
                let py = r * sin(theta)
                let pt = toScreenPoint(x: px, y: py, rect: rect)
                if i == 0 { polarPath.move(to: pt) }
                else { polarPath.addLine(to: pt) }
            }
            UIColor(red: 1.0, green: 0.584, blue: 0.0, alpha: 1.0).setStroke()
            polarPath.lineWidth = 2.5
            polarPath.stroke()
            return
        }

        let maxPlotY = max(200.0, spanY * 6.0)
        let a = min(integralXMin, integralXMax)
        let b = max(integralXMin, integralXMax)
        if b > a {
            let posPath = UIBezierPath()
            let negPath = UIBezierPath()
            let shadeSteps = 260
            let sdx = (b - a) / Double(shadeSteps)

            for i in 0..<shadeSteps {
                let x1 = a + Double(i) * sdx
                let x2 = x1 + sdx
                let y1 = fRaw(x1, 0, 0)
                let y2 = fRaw(x2, 0, 0)
                guard y1.isFinite && y2.isFinite && abs(y1) <= maxPlotY && abs(y2) <= maxPlotY else { continue }

                let p1 = toScreenPoint(x: x1, y: y1, rect: rect)
                let p2 = toScreenPoint(x: x2, y: y2, rect: rect)
                let b1 = toScreenPoint(x: x1, y: 0, rect: rect)
                let b2 = toScreenPoint(x: x2, y: 0, rect: rect)

                let sub = UIBezierPath()
                sub.move(to: b1)
                sub.addLine(to: p1)
                sub.addLine(to: p2)
                sub.addLine(to: b2)
                sub.close()

                if (y1 + y2) >= 0 {
                    posPath.append(sub)
                } else {
                    negPath.append(sub)
                }
            }

            UIColor(red: 1.0, green: 0.584, blue: 0.0, alpha: 0.30).setFill()
            posPath.fill()
            UIColor(red: 0.04, green: 0.52, blue: 1.0, alpha: 0.32).setFill()
            negPath.fill()

            let boundDash: [CGFloat] = [4, 3]
            let boundLine = UIBezierPath()
            let paTop = toScreenPoint(x: a, y: viewYMax, rect: rect)
            let paBot = toScreenPoint(x: a, y: viewYMin, rect: rect)
            let pbTop = toScreenPoint(x: b, y: viewYMax, rect: rect)
            let pbBot = toScreenPoint(x: b, y: viewYMin, rect: rect)
            boundLine.move(to: paTop); boundLine.addLine(to: paBot)
            boundLine.move(to: pbTop); boundLine.addLine(to: pbBot)
            boundLine.setLineDash(boundDash, count: 2, phase: 0)
            UIColor(white: 0.85, alpha: 0.55).setStroke()
            boundLine.lineWidth = 1.0
            boundLine.stroke()
        }

        let sampleCount = 600
        let dx = (viewXMax - viewXMin) / Double(sampleCount)

        let derivPath = UIBezierPath()
        var hasPrevDeriv = false
        var prevDerivVal = 0.0
        for i in 0...sampleCount {
            let x = viewXMin + Double(i) * dx
            let dy = NumericalCalculusEngine.partialDerivativeX(fSafe, x0: x, y0: 0)
            if !dy.isFinite || abs(dy) > maxPlotY || (hasPrevDeriv && NumericalCalculusEngine.isDiscontinuousSegment(v1: prevDerivVal, v2: dy, jumpLimit: spanY * 1.2)) {
                hasPrevDeriv = false
                continue
            }
            let pt = toScreenPoint(x: x, y: dy, rect: rect)
            if !hasPrevDeriv { derivPath.move(to: pt); hasPrevDeriv = true }
            else { derivPath.addLine(to: pt) }
            prevDerivVal = dy
        }
        UIColor(red: 0.20, green: 0.78, blue: 0.35, alpha: 0.88).setStroke()
        derivPath.lineWidth = 1.6
        let dash: [CGFloat] = [5, 4]
        derivPath.setLineDash(dash, count: 2, phase: 0)
        derivPath.stroke()

        let curvePath = UIBezierPath()
        var hasPrevPoint = false
        var prevYVal = 0.0
        for i in 0...sampleCount {
            let x = viewXMin + Double(i) * dx
            let yVal = fRaw(x, 0, 0)
            if !yVal.isFinite || abs(yVal) > maxPlotY || (hasPrevPoint && NumericalCalculusEngine.isDiscontinuousSegment(v1: prevYVal, v2: yVal, jumpLimit: spanY * 1.2)) {
                hasPrevPoint = false
                continue
            }
            let pt = toScreenPoint(x: x, y: yVal, rect: rect)
            if !hasPrevPoint { curvePath.move(to: pt); hasPrevPoint = true }
            else { curvePath.addLine(to: pt) }
            prevYVal = yVal
        }
        UIColor(red: 1.0, green: 0.584, blue: 0.0, alpha: 1.0).setStroke()
        curvePath.lineWidth = 2.6
        curvePath.stroke()

        let legendText = "  ■ 橙: 正面积(+)  ■ 蓝: 负面积(−)  --- 绿: 导数 f'(x) | 单指平移·双指分轴拉伸  " as NSString
        let legendAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10.0, weight: .medium),
            .foregroundColor: UIColor(white: 0.88, alpha: 1.0),
            .backgroundColor: UIColor(white: 0.12, alpha: 0.88)
        ]
        legendText.draw(at: CGPoint(x: 12, y: rect.height - 96), withAttributes: legendAttrs)

        let yAtX0 = fRaw(x0, 0, 0)
        if yAtX0.isFinite && abs(yAtX0) < maxPlotY {
            let slope = NumericalCalculusEngine.partialDerivativeX(fSafe, x0: x0, y0: 0)
            let pCenter = toScreenPoint(x: x0, y: yAtX0, rect: rect)
            let dot = UIBezierPath(arcCenter: pCenter, radius: 5.0, startAngle: 0, endAngle: CGFloat(Double.pi * 2), clockwise: true)
            UIColor.white.setFill()
            dot.fill()

            if activeProbeX != nil {
                let probeText = String(format: " x=%.2f, f(x)=%.3f, 斜率f'(x)=%.3f ", x0, yAtX0, slope) as NSString
                let probeAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 11.5, weight: .semibold),
                    .foregroundColor: UIColor.black,
                    .backgroundColor: UIColor(red: 1.0, green: 0.584, blue: 0.0, alpha: 0.95)
                ]
                let bx = max(12, min(rect.width - 245, pCenter.x - 110))
                let by = max(100, pCenter.y - 34)
                probeText.draw(at: CGPoint(x: bx, y: by), withAttributes: probeAttrs)
            }
        }
    }
}

// MARK: - 11. SceneKit 3D 几何构建器 (支持透视半透明材质、内部坐标轴穿透显示与全区域可拉伸坐标轴)

final class Surface3DBuilder {

    static func prewarm3DCaches() {
        // 预热字体与基础材质
        _ = computeNiceTickStep(forLength: 5.0)
    }

    static func heightColor(t: Float, alpha: Float = 1.0) -> SCNVector4 {
        let clamped = max(0.0, min(1.0, t))
        let r = max(0.0, min(1.0, 1.5 - abs(4.0 * clamped - 3.0)))
        let g = max(0.0, min(1.0, 1.5 - abs(4.0 * clamped - 2.0)))
        let b = max(0.0, min(1.0, 1.5 - abs(4.0 * clamped - 1.0)))
        return SCNVector4(r, g, b, alpha)
    }

    /// 提取隐式球面/椭球方程 F(x,y,z)=C 的三轴半径 (rx, ry, rz)
    static func extractEllipsoidRadii(expression: String, fallbackRhs: Double = 1.0) -> (Double, Double, Double) {
        let fSafe = MultivariateMathParser.compileSafe3D(expression)
        let f0 = fSafe(0, 0, 0)
        let rSquared = max(0.0, -f0)
        let ax = max(0.0, fSafe(1, 0, 0) - f0)
        let by = max(0.0, fSafe(0, 1, 0) - f0)
        let cz = max(0.0, fSafe(0, 0, 1) - f0)

        if rSquared > 1e-4 && ax > 1e-4 && by > 1e-4 && cz > 1e-4 {
            return (sqrt(rSquared / ax), sqrt(rSquared / by), sqrt(rSquared / cz))
        }
        let r = max(1.0, sqrt(abs(fallbackRhs)))
        return (r, r, r)
    }

    /// 计算 3D 物体的真实外表面几何半径（用于防穿模相机最小安全距离计算，绝对禁止相机进入物体内部）
    static func computeObjectSurfaceRadius(params: CalculusInputParameters, isImplicitEquation: Bool) -> Float {
        if isImplicitEquation || params.coordMode == .implicitSurface {
            let (_, _, rhsVal) = MultivariateMathParser.normalizeEquationToZeroForm(params.expression)
            let (rx, ry, rz) = extractEllipsoidRadii(expression: params.expression, fallbackRhs: rhsVal)
            return Float(max(1.2, max(rx, max(ry, rz))))
        }
        let maxX = max(abs(params.xMin), abs(params.xMax))
        let maxY = max(abs(params.yMin), abs(params.yMax))
        let maxZ = max(abs(params.zMin), abs(params.zMax))
        switch params.pageType {
        case .singleIntegral:
            let fSafe = MultivariateMathParser.compileSafe3D(params.expression)
            let midX = 0.5 * (params.xMin + params.xMax)
            let rSample = max(abs(fSafe(params.xMin, 0, 0)), max(abs(fSafe(midX, 0, 0)), abs(fSafe(params.xMax, 0, 0))))
            let clampedR = min(20.0, max(1.5, rSample))
            return Float(max(2.0, sqrt(maxX * maxX + clampedR * clampedR)))
        case .doubleIntegral:
            return Float(max(2.5, sqrt(maxX * maxX + maxY * maxY)))
        case .tripleIntegral:
            return Float(max(2.2, sqrt(maxX * maxX + maxY * maxY + maxZ * maxZ)))
        }
    }

    /// 计算默认坐标轴基准长度（比物体外表面半径大 45%，确保正负全区域坐标轴穿出物体外部清晰可见）
    static func computeSceneBoundingRadius(params: CalculusInputParameters, isImplicitEquation: Bool) -> Float {
        let objRadius = computeObjectSurfaceRadius(params: params, isImplicitEquation: isImplicitEquation)
        return max(4.5, objRadius * 1.45)
    }

    /// 根据坐标轴半长智能计算整洁刻度步长 (1, 2, 5, 10, 20, 50...)
    static func computeNiceTickStep(forLength length: Float) -> Int {
        let rawStep = max(0.5, Double(length) / 5.0)
        let mag = pow(10.0, floor(log10(rawStep)))
        let residual = rawStep / mag
        let nice: Double
        if residual > 5.0 { nice = 10.0 * mag }
        else if residual > 2.2 { nice = 5.0 * mag }
        else if residual > 1.2 { nice = 2.0 * mag }
        else { nice = 1.0 * mag }
        return max(1, Int(round(nice)))
    }

    static func buildRevolutionDifferentialDiskNode(
        fSafe: (Double, Double, Double) -> Double,
        sliceX: Double,
        thickness: Double = 0.08
    ) -> SCNNode {
        let r = max(0.03, min(50.0, abs(fSafe(sliceX, 0, 0))))
        let cyl = SCNCylinder(radius: CGFloat(r), height: CGFloat(thickness))
        let mat = SCNMaterial()
        mat.diffuse.contents = UIColor(red: 1.0, green: 0.65, blue: 0.0, alpha: 0.88)
        mat.emission.contents = UIColor(red: 0.45, green: 0.25, blue: 0.0, alpha: 1.0)
        mat.isDoubleSided = true
        cyl.materials = [mat]

        let diskNode = SCNNode(geometry: cyl)
        diskNode.position = SCNVector3(Float(sliceX), 0, 0)
        diskNode.eulerAngles = SCNVector3(0, 0, Float.pi / 2.0)
        diskNode.renderingOrder = 5
        return diskNode
    }

    static func buildImplicitEquationSurfaceNode(expression: String, surfaceOpacity: CGFloat = 0.52) -> SCNNode {
        let container = SCNNode()
        let (_, _, rhsVal) = MultivariateMathParser.normalizeEquationToZeroForm(expression)
        let fSafe = MultivariateMathParser.compileSafe3D(expression)

        let f0 = fSafe(0, 0, 0)
        let rSquared = max(0.0, -f0)
        let ax = max(0.0, fSafe(1, 0, 0) - f0)
        let by = max(0.0, fSafe(0, 1, 0) - f0)
        let cz = max(0.0, fSafe(0, 0, 1) - f0)

        if rSquared > 1e-4 && ax > 1e-4 && by > 1e-4 && cz > 1e-4 {
            let rx = sqrt(rSquared / ax)
            let ry = sqrt(rSquared / by)
            let rz = sqrt(rSquared / cz)
            return buildParametricEllipsoidNode(rx: rx, ry: ry, rz: rz, surfaceOpacity: surfaceOpacity)
        }

        let n = 22
        let bound = max(2.2, sqrt(abs(rhsVal)) * 1.4)
        let step = (2.0 * bound) / Double(n)
        let tol = step * 1.15

        var allVerts: [SCNVector3] = []
        var allNorms: [SCNVector3] = []
        var allCols: [SCNVector4] = []
        var allIndices: [Int32] = []

        for i in 0...n {
            let x = -bound + Double(i) * step
            for j in 0...n {
                let y = -bound + Double(j) * step
                for k in 0...n {
                    let z = -bound + Double(k) * step
                    let val = fSafe(x, y, z)
                    if abs(val) < tol {
                        let ratio = Float((z + bound) / (2.0 * bound))
                        let col = heightColor(t: ratio, alpha: 1.0)
                        let s = Float(step * 0.48)
                        appendCubeToBuffers(
                            cx: Float(x), cy: Float(z), cz: Float(-y),
                            hx: s, hy: s, hz: s,
                            color: col,
                            verts: &allVerts, norms: &allNorms, cols: &allCols, indices: &allIndices
                        )
                    }
                }
            }
        }

        if !allIndices.isEmpty {
            container.addChildNode(makeMeshNode(vertices: allVerts, normals: allNorms, colors: allCols, indices: allIndices, opacity: surfaceOpacity))
        }
        return container
    }

    static func buildParametricEllipsoidNode(
        rx: Double, ry: Double, rz: Double,
        uSteps: Int = 52, vSteps: Int = 38,
        surfaceOpacity: CGFloat = 0.52
    ) -> SCNNode {
        let totalVerts = (uSteps + 1) * (vSteps + 1)
        var vertices: [SCNVector3] = []; vertices.reserveCapacity(totalVerts)
        var normals: [SCNVector3] = []; normals.reserveCapacity(totalVerts)
        var colors: [SCNVector4] = []; colors.reserveCapacity(totalVerts)

        for i in 0...vSteps {
            let v = Double(i) * Double.pi / Double(vSteps)
            let sinV = sin(v)
            let cosV = cos(v)
            let ratio = Float(1.0 - Double(i) / Double(vSteps))
            let col = heightColor(t: ratio, alpha: 1.0)

            for j in 0...uSteps {
                let u = Double(j) * 2.0 * Double.pi / Double(uSteps)
                let cosU = cos(u)
                let sinU = sin(u)

                let x = rx * sinV * cosU
                let y = ry * sinV * sinU
                let z = rz * cosV

                vertices.append(SCNVector3(Float(x), Float(z), Float(-y)))
                let nx = Float(sinV * cosU / max(0.01, rx))
                let ny = Float(cosV / max(0.01, rz))
                let nz = Float(-sinV * sinU / max(0.01, ry))
                let len = max(1e-5, sqrt(nx*nx + ny*ny + nz*nz))
                normals.append(SCNVector3(nx/len, ny/len, nz/len))
                colors.append(col)
            }
        }

        // 单面索引配合 mat.isDoubleSided = true，避免正反双面重复叠加导致透明度失效
        var indices: [Int32] = []
        indices.reserveCapacity(uSteps * vSteps * 6)
        let stride = Int32(uSteps + 1)
        for i in 0..<Int32(vSteps) {
            for j in 0..<Int32(uSteps) {
                let p0 = i * stride + j
                let p1 = p0 + 1
                let p2 = (i + 1) * stride + j
                let p3 = p2 + 1
                indices.append(contentsOf: [p0, p2, p1, p1, p2, p3])
            }
        }

        let holder = SCNNode()
        let meshNode = makeMeshNode(vertices: vertices, normals: normals, colors: colors, indices: indices, opacity: surfaceOpacity)
        holder.addChildNode(meshNode)

        // 添加三条精美的球面/椭球正交经纬线环，增强半透明球体的立体轮廓与坐标对位感
        let ringColor = UIColor(white: 0.95, alpha: 0.42)
        let ringSteps = 72
        var eqXY: [SCNVector3] = []
        var eqXZ: [SCNVector3] = []
        var eqYZ: [SCNVector3] = []
        for k in 0...ringSteps {
            let ang = Double(k) * 2.0 * Double.pi / Double(ringSteps)
            let c = cos(ang), s = sin(ang)
            eqXY.append(SCNVector3(Float(rx * c), 0, Float(-ry * s)))
            eqXZ.append(SCNVector3(Float(rx * c), Float(rz * s), 0))
            eqYZ.append(SCNVector3(0, Float(rz * s), Float(-ry * c)))
        }
        holder.addChildNode(buildPolylineNode(points: eqXY, color: ringColor))
        holder.addChildNode(buildPolylineNode(points: eqXZ, color: ringColor))
        holder.addChildNode(buildPolylineNode(points: eqYZ, color: ringColor))

        return holder
    }

    static func buildContourSliceAndProjectionNode(
        fSafe: (Double, Double, Double) -> Double,
        xMin: Double, xMax: Double, yMin: Double, yMax: Double, sliceZ: Double
    ) -> SCNNode {
        let container = SCNNode()
        container.renderingOrder = 15

        let corners: [SCNVector3] = [
            SCNVector3(Float(xMin), Float(sliceZ), Float(-yMin)),
            SCNVector3(Float(xMax), Float(sliceZ), Float(-yMin)),
            SCNVector3(Float(xMax), Float(sliceZ), Float(-yMax)),
            SCNVector3(Float(xMin), Float(sliceZ), Float(-yMax))
        ]
        let indices: [Int32] = [0, 1, 2, 0, 2, 3]
        let vSource = SCNGeometrySource(vertices: corners)
        let iData = indices.withUnsafeBufferPointer { Data(buffer: $0) }
        let elem = SCNGeometryElement(data: iData, primitiveType: .triangles, primitiveCount: 2, bytesPerIndex: MemoryLayout<Int32>.size)
        let planeGeom = SCNGeometry(sources: [vSource], elements: [elem])
        let planeMat = SCNMaterial()
        planeMat.diffuse.contents = UIColor(red: 1.0, green: 0.584, blue: 0.0, alpha: 0.22)
        planeMat.isDoubleSided = true
        planeMat.writesToDepthBuffer = false
        planeGeom.materials = [planeMat]
        container.addChildNode(SCNNode(geometry: planeGeom))

        let n = 60
        let dx = (xMax - xMin) / Double(n)
        let dy = (yMax - yMin) / Double(n)
        let levels = [-1.5, -0.75, 0.0, 0.75, 1.5, sliceZ]

        var lineVerts: [SCNVector3] = []
        var lineIndices: [Int32] = []
        let basePlaneY: Float = -2.8

        for lv in levels {
            let isCurrentSlice = abs(lv - sliceZ) < 1e-4
            let tol = max(0.06, (abs(dx) + abs(dy)) * 0.45)
            for i in 0..<n {
                let x = xMin + Double(i) * dx
                for j in 0..<n {
                    let y = yMin + Double(j) * dy
                    let z = fSafe(x, y, 0)
                    if abs(z - lv) < tol {
                        let p1 = SCNVector3(Float(x), basePlaneY, Float(-y))
                        let p2 = SCNVector3(Float(x + dx), basePlaneY, Float(-(y + dy)))
                        let idx = Int32(lineVerts.count)
                        lineVerts.append(p1); lineVerts.append(p2)
                        lineIndices.append(idx); lineIndices.append(idx + 1)

                        if isCurrentSlice {
                            let s1 = SCNVector3(Float(x), Float(lv), Float(-y))
                            let s2 = SCNVector3(Float(x + dx), Float(lv), Float(-(y + dy)))
                            let sIdx = Int32(lineVerts.count)
                            lineVerts.append(s1); lineVerts.append(s2)
                            lineIndices.append(sIdx); lineIndices.append(sIdx + 1)
                        }
                    }
                }
            }
        }

        if !lineIndices.isEmpty {
            let lvSrc = SCNGeometrySource(vertices: lineVerts)
            let liData = lineIndices.withUnsafeBufferPointer { Data(buffer: $0) }
            let lElem = SCNGeometryElement(data: liData, primitiveType: .line, primitiveCount: lineIndices.count / 2, bytesPerIndex: MemoryLayout<Int32>.size)
            let lGeom = SCNGeometry(sources: [lvSrc], elements: [lElem])
            let lMat = SCNMaterial()
            lMat.diffuse.contents = UIColor(red: 1.0, green: 0.584, blue: 0.0, alpha: 0.95)
            lMat.emission.contents = UIColor(red: 1.0, green: 0.584, blue: 0.0, alpha: 0.55)
            lGeom.materials = [lMat]
            container.addChildNode(SCNNode(geometry: lGeom))
        }

        return container
    }

    static func buildSurfaceNode(
        fRaw: (Double, Double, Double) -> Double,
        fSafe: (Double, Double, Double) -> Double,
        xMin: Double, xMax: Double, yMin: Double, yMax: Double,
        coordMode: CoordinateSystemMode = .cartesian,
        gridCount: Int = 52,
        surfaceOpacity: CGFloat = 0.58
    ) -> SCNNode {
        let n = max(16, gridCount)
        let totalCount = (n + 1) * (n + 1)
        let dx = (xMax - xMin) / Double(n)
        let dy = (yMax - yMin) / Double(n)

        var vertices: [SCNVector3] = []; vertices.reserveCapacity(totalCount)
        var normals: [SCNVector3] = []; normals.reserveCapacity(totalCount)
        var colors: [SCNVector4] = []; colors.reserveCapacity(totalCount)
        var validMask: [Bool] = []; validMask.reserveCapacity(totalCount)
        var zValues: [Double] = []; zValues.reserveCapacity(totalCount)

        var minZ = Double.greatestFiniteMagnitude
        var maxZ = -Double.greatestFiniteMagnitude

        for i in 0...n {
            let u = xMin + Double(i) * dx
            for j in 0...n {
                let v = yMin + Double(j) * dy
                let rawZ = fRaw(u, v, 0.0)
                if rawZ.isFinite && abs(rawZ) <= 45.0 {
                    let clampedZ = max(-25.0, min(25.0, rawZ))
                    zValues.append(clampedZ)
                    validMask.append(true)
                    if clampedZ < minZ { minZ = clampedZ }
                    if clampedZ > maxZ { maxZ = clampedZ }
                } else {
                    zValues.append(0.0)
                    validMask.append(false)
                }
            }
        }
        if minZ > maxZ { minZ = -1.0; maxZ = 1.0 }
        let spanZ = max(0.001, maxZ - minZ)

        var idx = 0
        for i in 0...n {
            let u = xMin + Double(i) * dx
            for j in 0...n {
                let v = yMin + Double(j) * dy
                let z = zValues[idx]

                if coordMode == .polarOrSpherical {
                    let r = max(0.0, u)
                    let px = r * cos(v)
                    let py = r * sin(v)
                    vertices.append(SCNVector3(Float(px), Float(z), Float(-py)))
                } else {
                    vertices.append(SCNVector3(Float(u), Float(z), Float(-v)))
                }

                let dfx = NumericalCalculusEngine.partialDerivativeX(fSafe, x0: u, y0: v)
                let dfy = NumericalCalculusEngine.partialDerivativeY(fSafe, x0: u, y0: v)
                let nx = Float(-dfx)
                let ny = Float(1.0)
                let nz = Float(dfy)
                let len = max(1e-5, sqrt(nx * nx + ny * ny + nz * nz))
                normals.append(SCNVector3(nx / len, ny / len, nz / len))

                let ratio = Float((z - minZ) / spanZ)
                colors.append(heightColor(t: ratio, alpha: 1.0))
                idx += 1
            }
        }

        var indices: [Int32] = []
        indices.reserveCapacity(n * n * 6)
        let rowStride = Int32(n + 1)
        let jumpLimit = 10.0

        for i in 0..<Int32(n) {
            for j in 0..<Int32(n) {
                let p0 = i * rowStride + j
                let p1 = p0 + 1
                let p2 = (i + 1) * rowStride + j
                let p3 = p2 + 1

                let i0 = Int(p0), i1 = Int(p1), i2 = Int(p2), i3 = Int(p3)
                if !(validMask[i0] && validMask[i1] && validMask[i2] && validMask[i3]) { continue }
                let z0 = zValues[i0], z1 = zValues[i1], z2 = zValues[i2], z3 = zValues[i3]
                if abs(z0 - z1) > jumpLimit || abs(z0 - z2) > jumpLimit ||
                   abs(z3 - z1) > jumpLimit || abs(z3 - z2) > jumpLimit { continue }

                indices.append(contentsOf: [p0, p2, p1, p1, p2, p3])
            }
        }

        return makeMeshNode(vertices: vertices, normals: normals, colors: colors, indices: indices, opacity: surfaceOpacity)
    }

    static func buildRiemannPrismsNode(
        _ fSafe: (Double, Double, Double) -> Double,
        xMin: Double, xMax: Double, yMin: Double, yMax: Double,
        nx: Int = 12, ny: Int = 12,
        surfaceOpacity: CGFloat = 0.42
    ) -> SCNNode {
        var allVerts: [SCNVector3] = []
        var allNorms: [SCNVector3] = []
        var allCols: [SCNVector4] = []
        var allIndices: [Int32] = []

        let dx = (xMax - xMin) / Double(nx)
        let dy = (yMax - yMin) / Double(ny)

        for i in 0..<nx {
            let x = xMin + (Double(i) + 0.5) * dx
            for j in 0..<ny {
                let y = yMin + (Double(j) + 0.5) * dy
                let z = max(-15.0, min(15.0, fSafe(x, y, 0.0)))
                let h = abs(z)
                guard h > 0.03 else { continue }

                let col = (z >= 0)
                    ? SCNVector4(1.0, 0.58, 0.0, 1.0)
                    : SCNVector4(0.04, 0.52, 1.0, 1.0)

                appendCubeToBuffers(
                    cx: Float(x), cy: Float(z * 0.5), cz: Float(-y),
                    hx: Float(dx * 0.43), hy: Float(h * 0.5), hz: Float(dy * 0.43),
                    color: col,
                    verts: &allVerts, norms: &allNorms, cols: &allCols, indices: &allIndices
                )
            }
        }

        return makeMeshNode(vertices: allVerts, normals: allNorms, colors: allCols, indices: allIndices, opacity: surfaceOpacity)
    }

    static func buildTangentPlaneNode(
        x0: Double, y0: Double, z0: Double, fx: Double, fy: Double, span: Double = 1.4
    ) -> SCNNode {
        let holder = SCNNode()
        holder.renderingOrder = 12

        let sp = SCNNode(geometry: SCNSphere(radius: CGFloat(max(0.11, span * 0.08))))
        sp.geometry?.firstMaterial?.diffuse.contents = UIColor.white
        sp.geometry?.firstMaterial?.emission.contents = UIColor(white: 0.7, alpha: 1.0)
        sp.position = SCNVector3(Float(x0), Float(z0), Float(-y0))
        holder.addChildNode(sp)

        let corners: [(Double, Double)] = [
            (x0 - span, y0 - span), (x0 + span, y0 - span),
            (x0 + span, y0 + span), (x0 - span, y0 + span)
        ]

        var verts: [SCNVector3] = []
        for (px, py) in corners {
            let pz = max(-150.0, min(150.0, z0 + fx * (px - x0) + fy * (py - y0)))
            verts.append(SCNVector3(Float(px), Float(pz), Float(-py)))
        }

        let indices: [Int32] = [0, 1, 2, 0, 2, 3]
        let vSource = SCNGeometrySource(vertices: verts)
        let iData = indices.withUnsafeBufferPointer { Data(buffer: $0) }
        let elem = SCNGeometryElement(data: iData, primitiveType: .triangles, primitiveCount: 2, bytesPerIndex: MemoryLayout<Int32>.size)
        let geom = SCNGeometry(sources: [vSource], elements: [elem])
        let mat = SCNMaterial()
        mat.diffuse.contents = UIColor(red: 1.0, green: 0.584, blue: 0.0, alpha: 0.60)
        mat.emission.contents = UIColor(red: 0.4, green: 0.2, blue: 0.0, alpha: 0.35)
        mat.isDoubleSided = true
        mat.writesToDepthBuffer = false
        geom.materials = [mat]
        holder.addChildNode(SCNNode(geometry: geom))

        return holder
    }

    static func buildSolidOfRevolutionNode(
        _ fSafe: (Double, Double, Double) -> Double,
        xMin: Double, xMax: Double,
        xSteps: Int = 48, thetaSteps: Int = 36,
        surfaceOpacity: CGFloat = 0.52
    ) -> SCNNode {
        let container = SCNNode()
        let a = min(xMin, xMax)
        let b = max(xMin, xMax)
        guard abs(b - a) > 1e-5 else { return container }

        let dx = (b - a) / Double(xSteps)
        let dTheta = (2.0 * Double.pi) / Double(thetaSteps)

        let totalCount = (xSteps + 1) * (thetaSteps + 1)
        var vertices: [SCNVector3] = []; vertices.reserveCapacity(totalCount)
        var normals: [SCNVector3] = []; normals.reserveCapacity(totalCount)
        var colors: [SCNVector4] = []; colors.reserveCapacity(totalCount)

        for i in 0...xSteps {
            let x = a + Double(i) * dx
            let r = min(25.0, abs(fSafe(x, 0, 0)))
            let dfx = NumericalCalculusEngine.partialDerivativeX(fSafe, x0: x, y0: 0)
            let ratio = Float(Double(i) / Double(max(1, xSteps)))
            let col = heightColor(t: ratio, alpha: 1.0)

            for j in 0...thetaSteps {
                let theta = Double(j) * dTheta
                let cosT = cos(theta)
                let sinT = sin(theta)

                let vx = Float(x)
                let vy = Float(r * cosT)
                let vz = Float(r * sinT)
                vertices.append(SCNVector3(vx, vy, vz))

                let nx = Float(-dfx)
                let ny = Float(cosT)
                let nz = Float(sinT)
                let len = max(1e-5, sqrt(nx * nx + ny * ny + nz * nz))
                normals.append(SCNVector3(nx / len, ny / len, nz / len))
                colors.append(col)
            }
        }

        var indices: [Int32] = []
        indices.reserveCapacity(xSteps * thetaSteps * 6)
        let rowStride = Int32(thetaSteps + 1)
        for i in 0..<Int32(xSteps) {
            for j in 0..<Int32(thetaSteps) {
                let p0 = i * rowStride + j
                let p1 = p0 + 1
                let p2 = (i + 1) * rowStride + j
                let p3 = p2 + 1
                indices.append(contentsOf: [p0, p2, p1, p1, p2, p3])
            }
        }

        container.addChildNode(makeMeshNode(vertices: vertices, normals: normals, colors: colors, indices: indices, opacity: surfaceOpacity))
        return container
    }

    static func buildTripleIntegralVoxelCloudNode(
        _ fSafe: (Double, Double, Double) -> Double,
        xMin: Double, xMax: Double, yMin: Double, yMax: Double, zMin: Double, zMax: Double,
        nGrid: Int = 7,
        surfaceOpacity: CGFloat = 0.55
    ) -> SCNNode {
        let holder = SCNNode()

        let w = abs(xMax - xMin)
        let d = abs(yMax - yMin)
        let h = abs(zMax - zMin)
        let cx = 0.5 * (xMin + xMax)
        let cy = 0.5 * (yMin + yMax)
        let cz = 0.5 * (zMin + zMax)

        let boxGeom = SCNBox(width: CGFloat(w), height: CGFloat(h), length: CGFloat(d), chamferRadius: 0)
        let wireMat = SCNMaterial()
        wireMat.diffuse.contents = UIColor(white: 0.50, alpha: 0.14)
        wireMat.isDoubleSided = true
        wireMat.writesToDepthBuffer = false
        boxGeom.materials = [wireMat]
        let boxNode = SCNNode(geometry: boxGeom)
        boxNode.position = SCNVector3(Float(cx), Float(cz), Float(-cy))
        boxNode.renderingOrder = 12
        holder.addChildNode(boxNode)

        let dx = (xMax - xMin) / Double(nGrid)
        let dy = (yMax - yMin) / Double(nGrid)
        let dz = (zMax - zMin) / Double(nGrid)

        var values: [Double] = []
        var coords: [(Double, Double, Double)] = []
        var minW = Double.greatestFiniteMagnitude
        var maxW = -Double.greatestFiniteMagnitude

        for i in 0..<nGrid {
            let x = xMin + (Double(i) + 0.5) * dx
            for j in 0..<nGrid {
                let y = yMin + (Double(j) + 0.5) * dy
                for k in 0..<nGrid {
                    let z = zMin + (Double(k) + 0.5) * dz
                    let val = fSafe(x, y, z)
                    values.append(val)
                    coords.append((x, y, z))
                    if val < minW { minW = val }
                    if val > maxW { maxW = val }
                }
            }
        }

        let spanW = max(1e-4, maxW - minW)
        let baseCubeHalf = Float(min(abs(dx), min(abs(dy), abs(dz))) * 0.34)

        var allVerts: [SCNVector3] = []
        var allNorms: [SCNVector3] = []
        var allCols: [SCNVector4] = []
        var allIndices: [Int32] = []

        for idx in 0..<coords.count {
            let (x, y, z) = coords[idx]
            let val = values[idx]
            let ratio = Float((val - minW) / spanW)
            let s = baseCubeHalf * (0.42 + 0.58 * ratio)
            guard s > 0.01 else { continue }
            let col = heightColor(t: ratio, alpha: 1.0)

            appendCubeToBuffers(
                cx: Float(x), cy: Float(z), cz: Float(-y),
                hx: s, hy: s, hz: s,
                color: col,
                verts: &allVerts, norms: &allNorms, cols: &allCols, indices: &allIndices
            )
        }

        if !allIndices.isEmpty {
            holder.addChildNode(makeMeshNode(vertices: allVerts, normals: allNorms, colors: allCols, indices: allIndices, opacity: surfaceOpacity))
        }
        return holder
    }

    private static func appendOrthogonalPlaneGrid(
        fSafe: (Double, Double, Double) -> Double,
        steps: Int,
        pointAt: (Int, Int) -> (Double, Double, Double),
        normal: SCNVector3,
        allVerts: inout [SCNVector3],
        allNorms: inout [SCNVector3],
        allCols: inout [SCNVector4],
        allIndices: inout [Int32]
    ) {
        let baseIndex = Int32(allVerts.count)
        var vals: [Double] = []
        var minV = Double.greatestFiniteMagnitude
        var maxV = -Double.greatestFiniteMagnitude

        for i in 0...steps {
            for j in 0...steps {
                let (x, y, z) = pointAt(i, j)
                let v = fSafe(x, y, z)
                vals.append(v)
                if v < minV { minV = v }
                if v > maxV { maxV = v }
            }
        }
        let span = max(1e-4, maxV - minV)
        var k = 0
        for i in 0...steps {
            for j in 0...steps {
                let (x, y, z) = pointAt(i, j)
                allVerts.append(SCNVector3(Float(x), Float(z), Float(-y)))
                allNorms.append(normal)
                let ratio = Float((vals[k] - minV) / span)
                allCols.append(heightColor(t: ratio, alpha: 1.0))
                k += 1
            }
        }
        let stride = Int32(steps + 1)
        for i in 0..<Int32(steps) {
            for j in 0..<Int32(steps) {
                let p0 = baseIndex + i * stride + j
                let p1 = p0 + 1
                let p2 = baseIndex + (i + 1) * stride + j
                let p3 = p2 + 1
                allIndices.append(contentsOf: [p0, p2, p1, p1, p2, p3])
            }
        }
    }

    static func buildTripleIntegralOrthogonalSlicesNode(
        _ fSafe: (Double, Double, Double) -> Double,
        xMin: Double, xMax: Double, yMin: Double, yMax: Double, zMin: Double, zMax: Double,
        steps: Int = 26,
        surfaceOpacity: CGFloat = 0.65
    ) -> SCNNode {
        let holder = SCNNode()
        let xm = 0.5 * (xMin + xMax)
        let ym = 0.5 * (yMin + yMax)
        let zm = 0.5 * (zMin + zMax)

        let dx = (xMax - xMin) / Double(steps)
        let dy = (yMax - yMin) / Double(steps)
        let dz = (zMax - zMin) / Double(steps)

        var allVerts: [SCNVector3] = []
        var allNorms: [SCNVector3] = []
        var allCols: [SCNVector4] = []
        var allIndices: [Int32] = []

        appendOrthogonalPlaneGrid(
            fSafe: fSafe,
            steps: steps,
            pointAt: { i, j in (xMin + Double(i) * dx, yMin + Double(j) * dy, zm) },
            normal: SCNVector3(0, 1, 0),
            allVerts: &allVerts, allNorms: &allNorms, allCols: &allCols, allIndices: &allIndices
        )
        appendOrthogonalPlaneGrid(
            fSafe: fSafe,
            steps: steps,
            pointAt: { i, j in (xMin + Double(i) * dx, ym, zMin + Double(j) * dz) },
            normal: SCNVector3(0, 0, 1),
            allVerts: &allVerts, allNorms: &allNorms, allCols: &allCols, allIndices: &allIndices
        )
        appendOrthogonalPlaneGrid(
            fSafe: fSafe,
            steps: steps,
            pointAt: { i, j in (xm, yMin + Double(i) * dy, zMin + Double(j) * dz) },
            normal: SCNVector3(1, 0, 0),
            allVerts: &allVerts, allNorms: &allNorms, allCols: &allCols, allIndices: &allIndices
        )

        holder.addChildNode(makeMeshNode(vertices: allVerts, normals: allNorms, colors: allCols, indices: allIndices, opacity: surfaceOpacity))
        return holder
    }

    private static func appendCubeToBuffers(
        cx: Float, cy: Float, cz: Float,
        hx: Float, hy: Float, hz: Float,
        color: SCNVector4,
        verts: inout [SCNVector3],
        norms: inout [SCNVector3],
        cols: inout [SCNVector4],
        indices: inout [Int32]
    ) {
        let faces: [([SCNVector3], SCNVector3)] = [
            ([SCNVector3(cx-hx, cy-hy, cz+hz), SCNVector3(cx+hx, cy-hy, cz+hz), SCNVector3(cx+hx, cy+hy, cz+hz), SCNVector3(cx-hx, cy+hy, cz+hz)], SCNVector3(0, 0, 1)),
            ([SCNVector3(cx+hx, cy-hy, cz-hz), SCNVector3(cx-hx, cy-hy, cz-hz), SCNVector3(cx-hx, cy+hy, cz-hz), SCNVector3(cx+hx, cy+hy, cz-hz)], SCNVector3(0, 0, -1)),
            ([SCNVector3(cx-hx, cy+hy, cz+hz), SCNVector3(cx+hx, cy+hy, cz+hz), SCNVector3(cx+hx, cy+hy, cz-hz), SCNVector3(cx-hx, cy+hy, cz-hz)], SCNVector3(0, 1, 0)),
            ([SCNVector3(cx-hx, cy-hy, cz-hz), SCNVector3(cx+hx, cy-hy, cz-hz), SCNVector3(cx+hx, cy-hy, cz+hz), SCNVector3(cx-hx, cy-hy, cz+hz)], SCNVector3(0, -1, 0)),
            ([SCNVector3(cx+hx, cy-hy, cz+hz), SCNVector3(cx+hx, cy-hy, cz-hz), SCNVector3(cx+hx, cy+hy, cz-hz), SCNVector3(cx+hx, cy+hy, cz+hz)], SCNVector3(1, 0, 0)),
            ([SCNVector3(cx-hx, cy-hy, cz-hz), SCNVector3(cx-hx, cy-hy, cz+hz), SCNVector3(cx-hx, cy+hy, cz+hz), SCNVector3(cx-hx, cy+hy, cz-hz)], SCNVector3(-1, 0, 0))
        ]
        for (fVerts, norm) in faces {
            let base = Int32(verts.count)
            for v in fVerts {
                verts.append(v); norms.append(norm); cols.append(color)
            }
            indices.append(contentsOf: [base, base + 1, base + 2, base, base + 2, base + 3])
        }
    }

    private static func makeMeshNode(
        vertices: [SCNVector3],
        normals: [SCNVector3],
        colors: [SCNVector4],
        indices: [Int32],
        opacity: CGFloat
    ) -> SCNNode {
        let vSrc = SCNGeometrySource(vertices: vertices)
        let nSrc = SCNGeometrySource(normals: normals)
        let colorData = colors.withUnsafeBufferPointer { Data(buffer: $0) }
        let cSrc = SCNGeometrySource(
            data: colorData,
            semantic: .color,
            vectorCount: colors.count,
            usesFloatComponents: true,
            componentsPerVector: 4,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<SCNVector4>.stride
        )
        let idxData = indices.withUnsafeBufferPointer { Data(buffer: $0) }
        let elem = SCNGeometryElement(
            data: idxData,
            primitiveType: .triangles,
            primitiveCount: indices.count / 3,
            bytesPerIndex: MemoryLayout<Int32>.size
        )
        let geom = SCNGeometry(sources: [vSrc, nSrc, cSrc], elements: [elem])
        let mat = SCNMaterial()
        mat.lightingModel = .blinn
        mat.isDoubleSided = true
        mat.transparency = opacity
        mat.blendMode = .alpha
        // 当处于半透/高透模式时关闭深度写入，确保球体/曲面内部的坐标轴与刻度文字 100% 清晰透视可见
        mat.writesToDepthBuffer = (opacity >= 0.90)
        geom.materials = [mat]

        let node = SCNNode(geometry: geom)
        node.renderingOrder = 10
        return node
    }

    /// 构建全区域（正负双向箭头 + 智能刻度 + 自发光穿透显示）的三维坐标轴与网格
    static func buildAxesAndGridNode(length: Float = 4.5, showGrid: Bool = true) -> SCNNode {
        let wrapper = SCNNode()
        wrapper.renderingOrder = -10
        let tickStep = computeNiceTickStep(forLength: length)
        wrapper.addChildNode(createAxesHierarchy(length: length, tickStep: tickStep))

        if showGrid {
            let maxTick = Int(floor(length / Float(tickStep))) * tickStep
            let boundF = Float(max(tickStep, maxTick))
            let gridColor = UIColor(white: 0.34, alpha: 0.58)
            var g = -maxTick
            while g <= maxTick {
                let gf = Float(g)
                wrapper.addChildNode(buildLineNode(from: SCNVector3(-boundF, 0, -gf), to: SCNVector3(boundF, 0, -gf), color: gridColor))
                wrapper.addChildNode(buildLineNode(from: SCNVector3(gf, 0, -boundF), to: SCNVector3(gf, 0, boundF), color: gridColor))
                g += tickStep
            }
        }
        return wrapper
    }

    private static func makeEmissiveMaterial(color: UIColor, emissionAlpha: CGFloat = 0.55) -> SCNMaterial {
        let mat = SCNMaterial()
        mat.diffuse.contents = color
        mat.emission.contents = color.withAlphaComponent(emissionAlpha)
        mat.readsFromDepthBuffer = true
        mat.writesToDepthBuffer = true
        return mat
    }

    private static func createAxesHierarchy(length: Float, tickStep: Int) -> SCNNode {
        let root = SCNNode()
        root.renderingOrder = -10
        let scaleFactor = max(0.85, length / 5.5)
        let axisRadius: CGFloat = CGFloat(0.026 * scaleFactor)

        let redColor = UIColor(red: 1.0, green: 0.30, blue: 0.26, alpha: 1.0)
        let greenColor = UIColor(red: 0.22, green: 0.88, blue: 0.42, alpha: 1.0)
        let blueColor = UIColor(red: 0.20, green: 0.65, blue: 1.0, alpha: 1.0)
        let textColor = UIColor(white: 0.94, alpha: 1.0)

        let redMat = makeEmissiveMaterial(color: redColor)
        let greenMat = makeEmissiveMaterial(color: greenColor)
        let blueMat = makeEmissiveMaterial(color: blueColor)
        let originMat = makeEmissiveMaterial(color: UIColor.white, emissionAlpha: 0.75)

        // 原点 O(0,0,0) 高亮球与标签
        let originSphere = SCNSphere(radius: CGFloat(0.065 * scaleFactor))
        originSphere.materials = [originMat]
        root.addChildNode(SCNNode(geometry: originSphere))
        root.addChildNode(makeTextBillboard("0", color: textColor, position: SCNVector3(-0.22 * scaleFactor, -0.24 * scaleFactor, 0.22 * scaleFactor), size: 0.26 * scaleFactor))

        let coneRadius = CGFloat(0.095 * scaleFactor)
        let coneHeight = CGFloat(0.28 * scaleFactor)
        let labelOffset = 0.42 * scaleFactor
        let endLabelSize = 0.30 * scaleFactor

        // 1. X 轴 (全区域 -X 到 +X，红色)
        let xCyl = SCNCylinder(radius: axisRadius, height: CGFloat(length * 2.0))
        xCyl.materials = [redMat]
        let xNode = SCNNode(geometry: xCyl)
        xNode.eulerAngles = SCNVector3(0, 0, Float.pi / 2)
        root.addChildNode(xNode)

        let xPosArrow = SCNCone(topRadius: 0, bottomRadius: coneRadius, height: coneHeight)
        xPosArrow.materials = [redMat]
        let xPosArrowNode = SCNNode(geometry: xPosArrow)
        xPosArrowNode.position = SCNVector3(length, 0, 0)
        xPosArrowNode.eulerAngles = SCNVector3(0, 0, -Float.pi / 2)
        root.addChildNode(xPosArrowNode)
        root.addChildNode(makeTextBillboard("+X", color: redColor, position: SCNVector3(length + labelOffset, 0.18 * scaleFactor, 0), size: endLabelSize))

        let xNegArrow = SCNCone(topRadius: 0, bottomRadius: coneRadius * 0.85, height: coneHeight * 0.85)
        xNegArrow.materials = [redMat]
        let xNegArrowNode = SCNNode(geometry: xNegArrow)
        xNegArrowNode.position = SCNVector3(-length, 0, 0)
        xNegArrowNode.eulerAngles = SCNVector3(0, 0, Float.pi / 2)
        root.addChildNode(xNegArrowNode)
        root.addChildNode(makeTextBillboard("−X", color: redColor, position: SCNVector3(-length - labelOffset, 0.18 * scaleFactor, 0), size: endLabelSize * 0.9))

        // 2. Z 轴 (全区域 -Z 到 +Z，竖直方向，蓝色)
        let zCyl = SCNCylinder(radius: axisRadius, height: CGFloat(length * 2.0))
        zCyl.materials = [blueMat]
        let zNode = SCNNode(geometry: zCyl)
        root.addChildNode(zNode)

        let zPosArrow = SCNCone(topRadius: 0, bottomRadius: coneRadius, height: coneHeight)
        zPosArrow.materials = [blueMat]
        let zPosArrowNode = SCNNode(geometry: zPosArrow)
        zPosArrowNode.position = SCNVector3(0, length, 0)
        root.addChildNode(zPosArrowNode)
        root.addChildNode(makeTextBillboard("+Z", color: blueColor, position: SCNVector3(0.22 * scaleFactor, length + labelOffset, 0), size: endLabelSize))

        let zNegArrow = SCNCone(topRadius: 0, bottomRadius: coneRadius * 0.85, height: coneHeight * 0.85)
        zNegArrow.materials = [blueMat]
        let zNegArrowNode = SCNNode(geometry: zNegArrow)
        zNegArrowNode.position = SCNVector3(0, -length, 0)
        zNegArrowNode.eulerAngles = SCNVector3(Float.pi, 0, 0)
        root.addChildNode(zNegArrowNode)
        root.addChildNode(makeTextBillboard("−Z", color: blueColor, position: SCNVector3(0.22 * scaleFactor, -length - labelOffset, 0), size: endLabelSize * 0.9))

        // 3. Y 轴 (全区域 -Y 到 +Y，深度方向，绿色)
        let yCyl = SCNCylinder(radius: axisRadius, height: CGFloat(length * 2.0))
        yCyl.materials = [greenMat]
        let yNode = SCNNode(geometry: yCyl)
        yNode.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
        root.addChildNode(yNode)

        let yPosArrow = SCNCone(topRadius: 0, bottomRadius: coneRadius, height: coneHeight)
        yPosArrow.materials = [greenMat]
        let yPosArrowNode = SCNNode(geometry: yPosArrow)
        yPosArrowNode.position = SCNVector3(0, 0, -length)
        yPosArrowNode.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
        root.addChildNode(yPosArrowNode)
        root.addChildNode(makeTextBillboard("+Y", color: greenColor, position: SCNVector3(0.18 * scaleFactor, 0.18 * scaleFactor, -length - labelOffset), size: endLabelSize))

        let yNegArrow = SCNCone(topRadius: 0, bottomRadius: coneRadius * 0.85, height: coneHeight * 0.85)
        yNegArrow.materials = [greenMat]
        let yNegArrowNode = SCNNode(geometry: yNegArrow)
        yNegArrowNode.position = SCNVector3(0, 0, length)
        yNegArrowNode.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
        root.addChildNode(yNegArrowNode)
        root.addChildNode(makeTextBillboard("−Y", color: greenColor, position: SCNVector3(0.18 * scaleFactor, 0.18 * scaleFactor, length + labelOffset), size: endLabelSize * 0.9))

        // 4. 正负全区域刻度球与自适应数字标签
        let maxTick = Int(floor(length / Float(tickStep))) * tickStep
        let rTick = CGFloat(0.048 * scaleFactor)
        let sz = 0.21 * scaleFactor
        var tick = -maxTick
        while tick <= maxTick {
            if tick != 0 {
                let tf = Float(tick)
                let labelStr = tick < 0 ? "−\(abs(tick))" : "\(tick)"

                let xTick = SCNSphere(radius: rTick); xTick.materials = [redMat]
                let xTickNode = SCNNode(geometry: xTick); xTickNode.position = SCNVector3(tf, 0, 0)
                root.addChildNode(xTickNode)
                root.addChildNode(makeTextBillboard(labelStr, color: textColor, position: SCNVector3(tf, -0.25 * scaleFactor, 0), size: sz))

                let yTick = SCNSphere(radius: rTick); yTick.materials = [greenMat]
                let yTickNode = SCNNode(geometry: yTick); yTickNode.position = SCNVector3(0, 0, -tf)
                root.addChildNode(yTickNode)
                root.addChildNode(makeTextBillboard(labelStr, color: textColor, position: SCNVector3(0.22 * scaleFactor, -0.20 * scaleFactor, -tf), size: sz))

                let zTick = SCNSphere(radius: rTick); zTick.materials = [blueMat]
                let zTickNode = SCNNode(geometry: zTick); zTickNode.position = SCNVector3(0, tf, 0)
                root.addChildNode(zTickNode)
                root.addChildNode(makeTextBillboard(labelStr, color: textColor, position: SCNVector3(0.25 * scaleFactor, tf, 0), size: sz))
            }
            tick += tickStep
        }
        return root
    }

    private static func makeTextBillboard(_ string: String, color: UIColor, position: SCNVector3, size: Float) -> SCNNode {
        let billboardHolder = SCNNode()
        billboardHolder.position = position
        billboardHolder.renderingOrder = -8
        let billboard = SCNBillboardConstraint()
        billboard.freeAxes = .all
        billboardHolder.constraints = [billboard]

        let textGeom = SCNText(string: string, extrusionDepth: 0.02)
        textGeom.font = UIFont.systemFont(ofSize: 1.0, weight: .bold)
        textGeom.flatness = 0.12
        let mat = SCNMaterial()
        mat.diffuse.contents = color
        mat.emission.contents = color.withAlphaComponent(0.65)
        textGeom.materials = [mat]

        let (minBound, maxBound) = textGeom.boundingBox
        let innerTextNode = SCNNode(geometry: textGeom)
        innerTextNode.pivot = SCNMatrix4MakeTranslation(
            (maxBound.x - minBound.x) * 0.5 + minBound.x,
            (maxBound.y - minBound.y) * 0.5 + minBound.y,
            0
        )
        innerTextNode.scale = SCNVector3(size, size, size)
        billboardHolder.addChildNode(innerTextNode)
        return billboardHolder
    }

    private static func buildLineNode(from p1: SCNVector3, to p2: SCNVector3, color: UIColor) -> SCNNode {
        let verts = [p1, p2]
        let indices: [Int32] = [0, 1]
        let vSource = SCNGeometrySource(vertices: verts)
        let iData = indices.withUnsafeBufferPointer { Data(buffer: $0) }
        let elem = SCNGeometryElement(data: iData, primitiveType: .line, primitiveCount: 1, bytesPerIndex: MemoryLayout<Int32>.size)
        let geom = SCNGeometry(sources: [vSource], elements: [elem])
        let mat = SCNMaterial()
        mat.diffuse.contents = color
        mat.emission.contents = color.withAlphaComponent(0.35)
        geom.materials = [mat]
        let node = SCNNode(geometry: geom)
        node.renderingOrder = -12
        return node
    }

    private static func buildPolylineNode(points: [SCNVector3], color: UIColor) -> SCNNode {
        guard points.count >= 2 else { return SCNNode() }
        var indices: [Int32] = []
        indices.reserveCapacity((points.count - 1) * 2)
        for i in 0..<(points.count - 1) {
            indices.append(Int32(i))
            indices.append(Int32(i + 1))
        }
        let vSource = SCNGeometrySource(vertices: points)
        let iData = indices.withUnsafeBufferPointer { Data(buffer: $0) }
        let elem = SCNGeometryElement(data: iData, primitiveType: .line, primitiveCount: points.count - 1, bytesPerIndex: MemoryLayout<Int32>.size)
        let geom = SCNGeometry(sources: [vSource], elements: [elem])
        let mat = SCNMaterial()
        mat.diffuse.contents = color
        mat.emission.contents = color.withAlphaComponent(0.45)
        geom.materials = [mat]
        let node = SCNNode(geometry: geom)
        node.renderingOrder = 8
        return node
    }
}

// MARK: - 12. 面向零基础新手的《使用说明书》视图控制器

final class CalculusUserManualViewController: UIViewController {

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .allButUpsideDown
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "新手使用说明书"
        view.backgroundColor = .black

        navigationController?.navigationBar.barTintColor = UIColor(red: 0.08, green: 0.08, blue: 0.09, alpha: 1.0)
        navigationController?.navigationBar.isTranslucent = false
        navigationController?.navigationBar.tintColor = UIColor(red: 1.0, green: 0.584, blue: 0.0, alpha: 1.0)
        navigationController?.navigationBar.titleTextAttributes = [
            .foregroundColor: UIColor.white,
            .font: UIFont.systemFont(ofSize: 16.5, weight: .semibold)
        ]

        let sysSettingsItem = UIBarButtonItem(title: "系统设置 ⚙", style: .plain, target: self, action: #selector(openSystemSettingsTapped))
        navigationItem.leftBarButtonItem = sysSettingsItem

        let doneItem = UIBarButtonItem(title: "关闭", style: .done, target: self, action: #selector(closeTapped))
        navigationItem.rightBarButtonItem = doneItem

        let scrollView = UIScrollView()
        scrollView.delaysContentTouches = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        let contentStack = UIStackView()
        contentStack.axis = .vertical
        contentStack.spacing = 12
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        let sections: [(String, String)] = [
            ("一、欢迎使用！10 秒认识屏幕布局",
             "如果你是第一次打开本软件，请把屏幕看作上下两部分（把手机横过来时会自动变成左右两部分）：\n• 【上方纯黑显示屏】：大号白字显示你输入的数学算式，下方的橙色字显示计算出的精确答案（遵循过程一致性：你输入整数或分数如 3/4、x²，结果与步骤自动输出纯分数 1/3 或 π/5；输入小数则输出纯小数，绝不混用）。\n• 【下方专业数学键盘】：\n  - 第一行蓝色键 `x, y, z` 是未知数变量；\n  - 深灰色键 `sin, cos, ln, exp` 是常见数学函数；\n  - 右侧橙色键 `÷, ×, −, +, =` 是四则运算与等于号（按 `3 ÷ 4` 直接显示为分数 `3/4`）。"),
            ("二、手把手：如何花 30 秒算出一道积分题？",
             "以计算定积分 ∫[0, 1] x² dx = 1/3 为例：\n1. 【选积分类型】：点击屏幕最顶部的 `∫ 定积分`（若算二重积分就点 `∬ 二重`，算三重积分就点 `∭ 三重`）。\n2. 【改积分上下限】：点击屏幕右上角的 `[0,1] ▾` 按钮，会展开上下限填空框（`x₁` 是下限，`x₂` 是上限，`x₀` 是求导切点）。点击你想改的框（框会亮起橙色边），直接按键盘输入数字（支持输入 `π`、`e` 或分数），输完再点一下 `收起 ▲` 即可隐藏。\n3. 【输入算式并按 =】：点一下黑色显示屏切回公式输入，按 `AC` 清空，用力深按蓝色的 `x` 输入 `x²`，最后按右下角橙色 `=` 键，橙色结果行立即显示 `= 1/3`！"),
            ("三、核心秘籍：iPhone X 的 3D Touch 重压怎么用？",
             "本软件针对 iPhone X 的压感屏做了两项极其顺手的重压快捷功能：\n• 【1. 重压键盘按键 → 输入右上角小字功能】\n  仔细看按键右上角印着的小字（例如 `sin` 右上角是反三角 `sin⁻¹`，`xⁿ` 右上角是平方 `^2`，`⌫` 右上角是全清 `AC`，橙色 `=` 右上角是 `方程=`）。\n  - **轻轻点按**：输入按键正中央的大字；\n  - **用力深按（3D Touch）**：感觉到手机震动一下后，会直接输入右上角的小字功能！\n  - **例子：怎么输入球面方程 x²+y²+z²=100？** 先依次输入 `x²+y²+z²`，然后**用力深按右下角橙色 `=` 键**打出等号 `=`，再输入 `100` 并轻按 `=`，即刻算出 `球体积 V = 4000π/3`！\n• 【2. 重压上方纯黑显示屏 → 弹出 2D / 3D 立体图像】\n  算完任何算式后，用手指**用力深按上方纯黑算式显示区**，就会直接弹出交互式几何图像页！"),
            ("四、在 2D / 3D 图像页里怎么自由平移、拉伸坐标轴与开启透视？",
             "进入图像页后，我们为你提供了全方位自由操控体验：\n• 【1. 自由移动图像（不再只能围绕中心点转）】：\n  - 点击右侧悬浮栏的 **「平移」** 按钮（亮起橙色 `平移中`），**单指滑动即可任意上下左右移动整个 3D 图像**；即使在旋转模式下，**双指按住拖动**也能随时平移图像！\n• 【2. 曲面透明透视（清晰看穿物体内部坐标轴）】：\n  - 3D 曲面默认开启 **「半透 (52%)」** 模式，你可以直接透过球体/曲面看清球心 `0` 与红(`X`)、绿(`Y`)、蓝(`Z`)三根坐标轴；点击右侧 **「半透/高透/实心」** 按钮可随时切换不同透明度。\n• 【3. 防穿模安全缩放（绝不钻进物体内部）】：\n  - 双指捏合放大时，系统会自动识别球体/曲面外表面半径并锁定最小安全距离，**绝不会穿入物体内部变成满屏纯色墙**。\n• 【4. 全区域双向坐标轴与自由拉伸】：\n  - 坐标轴完整显示 `+X/−X, +Y/−Y, +Z/−Z` 全部正负区域与刻度；拖动底部面板第一行的 **「坐标轴拉伸」滑块（0.6x ~ 2.8x）**，即可实时伸缩坐标轴与网格范围！"),
            ("五、如何在 iPhone「系统设置」中开启破题提示与真题？",
             "主屏幕 3D Touch 快捷菜单完整保留了【新手使用说明书】、【∫ 定积分】、【∬ 二重积分】、【∭ 三重积分】四项，软件的所有功能开关已集成进 iOS 自带的**【系统设置 (Settings)】**中：\n• 打开手机自带的 **【设置】App**，往下滑到底部找到 **【Calculus3D】**（或直接点击本页左上角的 **「系统设置 ⚙」** 一键跳转）；\n• 在系统设置中，你可以随时开启/关闭 **「💡 考场破题直觉与避坑提示（默认关）」**、**「🎯 考场答案遮挡自测模式」**、**「🔊 按键音与震动反馈」**，以及一键选择要载入的 8 道期末必考母题！"),
            ("六、开源使用授权与反抄袭防伪声明",
             "• **免费学习与使用**：本项目面向微积分学习者与教学场景免费开放使用。\n• **反抄袭数字水印保护**：核心符号积分引擎与 3D 渲染管线内嵌 `FNV-1a` 64 位防伪指纹（`0x43414C33445F4F53`）与 `GPL-3.0 / CC BY-NC-SA 4.0` 开源署名锁。欢迎正常学习使用与 Star/Fork，严禁抹除署名冒充个人课程作业、毕业设计或用于商业售卖。")
        ]

        for (heading, body) in sections {
            contentStack.addArrangedSubview(makeSectionCard(heading: heading, body: body))
        }

        let safe = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: safe.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: safe.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: safe.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: safe.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 14),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 14),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -14),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -24),
            contentStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -28)
        ])
    }

    private func makeSectionCard(heading: String, body: String) -> UIView {
        let card = UIView()
        card.backgroundColor = UIColor(red: 0.11, green: 0.11, blue: 0.13, alpha: 1.0)
        card.layer.cornerRadius = 14

        let hLabel = UILabel()
        hLabel.text = heading
        hLabel.font = UIFont.systemFont(ofSize: 15.0, weight: .bold)
        hLabel.textColor = UIColor(red: 1.0, green: 0.584, blue: 0.0, alpha: 1.0)
        hLabel.numberOfLines = 0
        hLabel.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(hLabel)

        let bLabel = UILabel()
        bLabel.text = body
        bLabel.font = UIFont.systemFont(ofSize: 13.0, weight: .regular)
        bLabel.textColor = UIColor(white: 0.88, alpha: 1.0)
        bLabel.numberOfLines = 0
        bLabel.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(bLabel)

        NSLayoutConstraint.activate([
            hLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            hLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            hLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            bLabel.topAnchor.constraint(equalTo: hLabel.bottomAnchor, constant: 6),
            bLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            bLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            bLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12)
        ])
        return card
    }

    @objc private func openSystemSettingsTapped() {
        TactileFeedbackManager.shared.playModifierTap()
        if let url = URL(string: UIApplication.openSettingsURLString), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }

    @objc private func closeTapped() {
        TactileFeedbackManager.shared.playModifierTap()
        dismiss(animated: true, completion: nil)
    }
}

// MARK: - 13. 主工作台控制器

final class Calculus3DViewController: UIViewController, UIViewControllerPreviewingDelegate {

    static weak var activeInstance: Calculus3DViewController?
    private static var pendingShortcutToOpen: UIApplicationShortcutItem?

    private let displayPanelView = UIView()
    private let keyboardBackgroundView = UIView()

    private let topControlRow = UIStackView()
    private let pageSelector = UISegmentedControl(items: ["∫ 定积分", "∬ 二重", "∭ 三重"])
    private let coordPillButton = UIButton(type: .system)
    private let boundsToggleHeader = UIButton(type: .system)

    private let formulaInputButton = UIControl()
    private let modeBadgeLabel = UILabel()
    private let expressionLabel = UILabel()
    private let primaryIntegralValueLabel = UILabel()

    private let onDemandDetailBox = UIView()
    private let onDemandScrollView = UIScrollView()
    private let onDemandDetailLabel = UILabel()
    private var onDemandBoxHeightConstraint: NSLayoutConstraint!
    private let onDemandSelector = UISegmentedControl(items: [
        "仅结果", "偏导 ∂f", "推导步骤", "极限/切面", "实验拟合"
    ])

    private let boundsDrawerContainer = UIView()
    private let boundsStack = UIStackView()
    private var boundsDrawerHeightConstraint: NSLayoutConstraint!
    private var isBoundsDrawerExpanded: Bool = false

    // 默认切点设为整数 "1"，避免默认带小数点影响分数模式判断
    private let xMinControl = BoundsInputButton(title: "x₁", initialValue: "0")
    private let xMaxControl = BoundsInputButton(title: "x₂", initialValue: "1")
    private let x0Control   = BoundsInputButton(title: "x₀", initialValue: "1")
    private let yMinControl = BoundsInputButton(title: "y₁", initialValue: "-2")
    private let yMaxControl = BoundsInputButton(title: "y₂", initialValue: "2")
    private let y0Control   = BoundsInputButton(title: "y₀", initialValue: "1")
    private let zMinControl = BoundsInputButton(title: "z₁", initialValue: "-1")
    private let zMaxControl = BoundsInputButton(title: "z₂", initialValue: "1")
    private let boundsRow2Stack = UIStackView()

    private weak var activeBoundsControl: BoundsInputButton?
    private let forceHintToast = UILabel()

    private let keypadContainer = UIStackView()
    private let topVariableRowStack = UIStackView()

    private var portraitConstraints: [NSLayoutConstraint] = []
    private var landscapeConstraints: [NSLayoutConstraint] = []
    private var currentIsLandscape: Bool?

    private var currentPage: IntegralPageType = .singleIntegral
    private var currentCoordMode: CoordinateSystemMode = .cartesian
    private var currentDisplayCategory: OnDemandDisplayCategory = .primaryOnly
    private var latestAnalysis: FullCalculusAnalysis?
    private var isAnswerMaskedForSelfTest: Bool = false
    private var lastAppliedPresetIndex: Int = -1

    private var rawExpressions: [IntegralPageType: String] = [
        .singleIntegral: "2x",
        .doubleIntegral: "sin(x)*cos(y)",
        .tripleIntegral: "x^2+y^2+z^2=1"
    ]

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .allButUpsideDown
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        Calculus3DViewController.activeInstance = self
        view.backgroundColor = .black

        CalculusAppSettings.shared.registerDefaults()
        TactileFeedbackManager.shared.prepareAll()
        Surface3DBuilder.prewarm3DCaches()

        setupDisplayAndKeypadPanels()
        setupOriginalIntegratedCalculatorKeypad()
        register3DTouchPeekAndPop()
        setupHomeScreen3DTouchAndSystemSettingsHooks()
        syncSystemSettingsState()

        pageSelector.selectedSegmentIndex = IntegralPageType.singleIntegral.rawValue
        onDemandSelector.selectedSegmentIndex = OnDemandDisplayCategory.primaryOnly.rawValue
        applyPageConfiguration(for: .singleIntegral)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let isLandscape = view.bounds.width > view.bounds.height
        if currentIsLandscape != isLandscape {
            currentIsLandscape = isLandscape
            applyOrientationLayout(isLandscape: isLandscape)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if let item = Calculus3DViewController.pendingShortcutToOpen {
            Calculus3DViewController.pendingShortcutToOpen = nil
            executeShortcutItemSafely(item)
        }
    }

    private func setupHomeScreen3DTouchAndSystemSettingsHooks() {
        let staticItems = Bundle.main.infoDictionary?["UIApplicationShortcutItems"] as? [[String: Any]] ?? []
        if staticItems.isEmpty {
            UIApplication.shared.shortcutItems = [
                UIApplicationShortcutItem(type: "com.calculus3d.manual", localizedTitle: "新手使用说明书", localizedSubtitle: "零基础操作与3D Touch指南", icon: UIApplicationShortcutIcon(type: .bookmark), userInfo: nil),
                UIApplicationShortcutItem(type: "com.calculus3d.single", localizedTitle: "∫ 定积分计算", localizedSubtitle: nil, icon: UIApplicationShortcutIcon(type: .compose), userInfo: nil),
                UIApplicationShortcutItem(type: "com.calculus3d.double", localizedTitle: "∬ 二重积分计算", localizedSubtitle: nil, icon: UIApplicationShortcutIcon(type: .compose), userInfo: nil),
                UIApplicationShortcutItem(type: "com.calculus3d.triple", localizedTitle: "∭ 三重积分计算", localizedSubtitle: nil, icon: UIApplicationShortcutIcon(type: .compose), userInfo: nil)
            ]
        } else {
            UIApplication.shared.shortcutItems = []
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(systemSettingsDidChange),
            name: UserDefaults.didChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(systemSettingsDidChange),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            forName: UIApplication.didFinishLaunchingNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            if let item = note.userInfo?[UIApplication.LaunchOptionsKey.shortcutItem] as? UIApplicationShortcutItem {
                if self?.view.window != nil {
                    self?.executeShortcutItemSafely(item)
                } else {
                    Calculus3DViewController.pendingShortcutToOpen = item
                }
            }
        }

        guard let delegate = UIApplication.shared.delegate else { return }
        let delegateClass: AnyClass = object_getClass(delegate)!
        let selector = #selector(UIApplicationDelegate.application(_:performActionFor:completionHandler:))

        let block: @convention(block) (AnyObject, UIApplication, UIApplicationShortcutItem, @escaping (Bool) -> Void) -> Void = { _, _, item, completion in
            DispatchQueue.main.async {
                if let vc = Calculus3DViewController.activeInstance, vc.view.window != nil {
                    vc.executeShortcutItemSafely(item)
                } else {
                    Calculus3DViewController.pendingShortcutToOpen = item
                }
                completion(true)
            }
        }
        let imp = imp_implementationWithBlock(block)
        if !class_addMethod(delegateClass, selector, imp, "v@:@@@?") {
            if let method = class_getInstanceMethod(delegateClass, selector) {
                method_setImplementation(method, imp)
            }
        }
    }

    @objc private func systemSettingsDidChange() {
        DispatchQueue.main.async { [weak self] in
            self?.syncSystemSettingsState()
        }
    }

    private func syncSystemSettingsState() {
        UserDefaults.standard.synchronize()
        let hintsOn = CalculusAppSettings.shared.isExamHintsEnabled
        onDemandSelector.setTitle(hintsOn ? "破题直觉" : "极限/切面", forSegmentAt: 3)
        onDemandSelector.setTitle(hintsOn ? "避坑/拟合" : "实验拟合", forSegmentAt: 4)

        let presetIdx = CalculusAppSettings.shared.selectedExamPresetIndex
        if presetIdx >= 0 && presetIdx < ExamIntuitionCoachEngine.classicExamProblems.count && presetIdx != lastAppliedPresetIndex {
            lastAppliedPresetIndex = presetIdx
            let preset = ExamIntuitionCoachEngine.classicExamProblems[presetIdx]
            loadExamProblemPreset(preset)
            return
        } else if presetIdx < 0 {
            lastAppliedPresetIndex = -1
        }

        if !hintsOn {
            isAnswerMaskedForSelfTest = false
        }
        recalculateAll()
    }

    func executeShortcutItemSafely(_ item: UIApplicationShortcutItem) {
        let work = { [weak self] in
            guard let self = self else { return }
            if item.type.contains("manual") {
                self.presentUserManualModal()
            } else if item.type.contains("single") {
                self.pageSelector.selectedSegmentIndex = 0
                self.applyPageConfiguration(for: .singleIntegral)
            } else if item.type.contains("double") {
                self.pageSelector.selectedSegmentIndex = 1
                self.applyPageConfiguration(for: .doubleIntegral)
            } else if item.type.contains("triple") {
                self.pageSelector.selectedSegmentIndex = 2
                self.applyPageConfiguration(for: .tripleIntegral)
            }
        }

        if presentedViewController != nil {
            dismiss(animated: false, completion: work)
        } else {
            work()
        }
    }

    func presentUserManualModal() {
        TactileFeedbackManager.shared.playModifierTap()
        let manualVC = CalculusUserManualViewController()
        let nav = UINavigationController(rootViewController: manualVC)
        nav.modalPresentationStyle = .fullScreen
        present(nav, animated: true, completion: nil)
    }

    private func setupDisplayAndKeypadPanels() {
        let safe = view.safeAreaLayoutGuide

        displayPanelView.backgroundColor = .black
        displayPanelView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(displayPanelView)

        keyboardBackgroundView.backgroundColor = .black
        keyboardBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(keyboardBackgroundView)

        styleDarkSegmentedControl(pageSelector, fontSize: 12.0)
        pageSelector.addTarget(self, action: #selector(pageSegmentChanged), for: .valueChanged)

        coordPillButton.backgroundColor = UIColor(red: 0.13, green: 0.13, blue: 0.15, alpha: 1.0)
        coordPillButton.layer.cornerRadius = 14
        coordPillButton.setTitle("直角 ▾", for: .normal)
        coordPillButton.setTitleColor(UIColor(red: 1.0, green: 0.584, blue: 0.0, alpha: 1.0), for: .normal)
        coordPillButton.titleLabel?.font = UIFont.systemFont(ofSize: 11.5, weight: .semibold)
        coordPillButton.contentEdgeInsets = UIEdgeInsets(top: 0, left: 9, bottom: 0, right: 9)
        coordPillButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        coordPillButton.setContentHuggingPriority(.required, for: .horizontal)
        coordPillButton.addTarget(self, action: #selector(coordPillTapped), for: .touchUpInside)

        boundsToggleHeader.backgroundColor = UIColor(red: 0.13, green: 0.13, blue: 0.15, alpha: 1.0)
        boundsToggleHeader.layer.cornerRadius = 14
        boundsToggleHeader.setTitle("[0,1] ▾", for: .normal)
        boundsToggleHeader.setTitleColor(UIColor(white: 0.86, alpha: 1.0), for: .normal)
        boundsToggleHeader.titleLabel?.font = UIFont.systemFont(ofSize: 11.5, weight: .medium)
        boundsToggleHeader.contentEdgeInsets = UIEdgeInsets(top: 0, left: 9, bottom: 0, right: 9)
        boundsToggleHeader.setContentCompressionResistancePriority(.required, for: .horizontal)
        boundsToggleHeader.setContentHuggingPriority(.required, for: .horizontal)
        boundsToggleHeader.addTarget(self, action: #selector(toggleBoundsDrawerTapped), for: .touchUpInside)

        topControlRow.axis = .horizontal
        topControlRow.spacing = 6
        topControlRow.alignment = .fill
        topControlRow.translatesAutoresizingMaskIntoConstraints = false
        topControlRow.addArrangedSubview(pageSelector)
        topControlRow.addArrangedSubview(coordPillButton)
        topControlRow.addArrangedSubview(boundsToggleHeader)
        displayPanelView.addSubview(topControlRow)

        boundsDrawerContainer.clipsToBounds = true
        boundsDrawerContainer.translatesAutoresizingMaskIntoConstraints = false
        displayPanelView.addSubview(boundsDrawerContainer)

        boundsStack.axis = .vertical
        boundsStack.spacing = 5
        boundsStack.distribution = .fillEqually
        boundsStack.translatesAutoresizingMaskIntoConstraints = false
        boundsDrawerContainer.addSubview(boundsStack)

        let allBoundsControls = [
            xMinControl, xMaxControl, x0Control,
            yMinControl, yMaxControl, y0Control,
            zMinControl, zMaxControl
        ]
        for ctrl in allBoundsControls {
            ctrl.addTarget(self, action: #selector(boundsControlTapped(_:)), for: .touchDown)
        }

        let boundsRow1Stack = UIStackView(arrangedSubviews: [xMinControl, xMaxControl, x0Control])
        boundsRow1Stack.axis = .horizontal
        boundsRow1Stack.spacing = 5
        boundsRow1Stack.distribution = .fillEqually

        boundsRow2Stack.axis = .horizontal
        boundsRow2Stack.spacing = 5
        boundsRow2Stack.distribution = .fillEqually

        boundsStack.addArrangedSubview(boundsRow1Stack)
        boundsStack.addArrangedSubview(boundsRow2Stack)
        boundsDrawerHeightConstraint = boundsDrawerContainer.heightAnchor.constraint(equalToConstant: 0)

        formulaInputButton.backgroundColor = .black
        formulaInputButton.clipsToBounds = true
        formulaInputButton.addTarget(self, action: #selector(formulaBoxTapped), for: .touchUpInside)
        formulaInputButton.translatesAutoresizingMaskIntoConstraints = false
        displayPanelView.addSubview(formulaInputButton)

        modeBadgeLabel.text = "Rad · 直角坐标 · 重压算式看图像"
        modeBadgeLabel.font = UIFont.systemFont(ofSize: 11.5, weight: .regular)
        modeBadgeLabel.textColor = UIColor(white: 0.52, alpha: 1.0)
        modeBadgeLabel.lineBreakMode = .byTruncatingTail
        modeBadgeLabel.isUserInteractionEnabled = false
        modeBadgeLabel.translatesAutoresizingMaskIntoConstraints = false
        formulaInputButton.addSubview(modeBadgeLabel)

        expressionLabel.font = UIFont.systemFont(ofSize: 34, weight: .light)
        expressionLabel.textColor = .white
        expressionLabel.textAlignment = .right
        expressionLabel.adjustsFontSizeToFitWidth = true
        expressionLabel.minimumScaleFactor = 0.40
        expressionLabel.lineBreakMode = .byTruncatingHead
        expressionLabel.isUserInteractionEnabled = false
        expressionLabel.translatesAutoresizingMaskIntoConstraints = false
        formulaInputButton.addSubview(expressionLabel)

        primaryIntegralValueLabel.font = UIFont.systemFont(ofSize: 20, weight: .semibold)
        primaryIntegralValueLabel.textColor = UIColor(red: 1.0, green: 0.584, blue: 0.0, alpha: 1.0)
        primaryIntegralValueLabel.textAlignment = .right
        primaryIntegralValueLabel.adjustsFontSizeToFitWidth = true
        primaryIntegralValueLabel.minimumScaleFactor = 0.55
        primaryIntegralValueLabel.isUserInteractionEnabled = false
        primaryIntegralValueLabel.translatesAutoresizingMaskIntoConstraints = false
        formulaInputButton.addSubview(primaryIntegralValueLabel)

        onDemandDetailBox.backgroundColor = UIColor(red: 0.09, green: 0.09, blue: 0.11, alpha: 1.0)
        onDemandDetailBox.layer.cornerRadius = 10
        onDemandDetailBox.clipsToBounds = true
        onDemandDetailBox.translatesAutoresizingMaskIntoConstraints = false
        displayPanelView.addSubview(onDemandDetailBox)

        onDemandScrollView.showsVerticalScrollIndicator = true
        onDemandScrollView.delaysContentTouches = false
        onDemandScrollView.translatesAutoresizingMaskIntoConstraints = false
        onDemandDetailBox.addSubview(onDemandScrollView)

        onDemandDetailLabel.font = UIFont.systemFont(ofSize: 11.5, weight: .regular)
        onDemandDetailLabel.textColor = UIColor(white: 0.90, alpha: 1.0)
        onDemandDetailLabel.numberOfLines = 0
        onDemandDetailLabel.translatesAutoresizingMaskIntoConstraints = false
        onDemandScrollView.addSubview(onDemandDetailLabel)

        onDemandBoxHeightConstraint = onDemandDetailBox.heightAnchor.constraint(equalToConstant: 0)

        styleDarkSegmentedControl(onDemandSelector, fontSize: 11.0)
        onDemandSelector.addTarget(self, action: #selector(onDemandCategoryChanged), for: .valueChanged)
        onDemandSelector.translatesAutoresizingMaskIntoConstraints = false
        displayPanelView.addSubview(onDemandSelector)

        keypadContainer.axis = .vertical
        keypadContainer.distribution = .fillEqually
        keypadContainer.spacing = 7
        keypadContainer.translatesAutoresizingMaskIntoConstraints = false
        keyboardBackgroundView.addSubview(keypadContainer)

        forceHintToast.backgroundColor = UIColor(red: 1.0, green: 0.584, blue: 0.0, alpha: 0.95)
        forceHintToast.textColor = .black
        forceHintToast.font = UIFont.systemFont(ofSize: 12, weight: .bold)
        forceHintToast.textAlignment = .center
        forceHintToast.layer.cornerRadius = 13
        forceHintToast.layer.masksToBounds = true
        forceHintToast.alpha = 0.0
        forceHintToast.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(forceHintToast)

        NSLayoutConstraint.activate([
            topControlRow.topAnchor.constraint(equalTo: displayPanelView.topAnchor, constant: 4),
            topControlRow.leadingAnchor.constraint(equalTo: displayPanelView.leadingAnchor, constant: 12),
            topControlRow.trailingAnchor.constraint(equalTo: displayPanelView.trailingAnchor, constant: -12),
            topControlRow.heightAnchor.constraint(equalToConstant: 28),

            boundsDrawerContainer.topAnchor.constraint(equalTo: topControlRow.bottomAnchor, constant: 4),
            boundsDrawerContainer.leadingAnchor.constraint(equalTo: displayPanelView.leadingAnchor, constant: 12),
            boundsDrawerContainer.trailingAnchor.constraint(equalTo: displayPanelView.trailingAnchor, constant: -12),
            boundsDrawerHeightConstraint,

            boundsStack.topAnchor.constraint(equalTo: boundsDrawerContainer.topAnchor),
            boundsStack.leadingAnchor.constraint(equalTo: boundsDrawerContainer.leadingAnchor),
            boundsStack.trailingAnchor.constraint(equalTo: boundsDrawerContainer.trailingAnchor),
            boundsStack.bottomAnchor.constraint(equalTo: boundsDrawerContainer.bottomAnchor),

            formulaInputButton.topAnchor.constraint(equalTo: boundsDrawerContainer.bottomAnchor, constant: 2),
            formulaInputButton.leadingAnchor.constraint(equalTo: displayPanelView.leadingAnchor, constant: 12),
            formulaInputButton.trailingAnchor.constraint(equalTo: displayPanelView.trailingAnchor, constant: -12),
            formulaInputButton.bottomAnchor.constraint(equalTo: onDemandDetailBox.topAnchor, constant: -3),

            modeBadgeLabel.topAnchor.constraint(equalTo: formulaInputButton.topAnchor, constant: 2),
            modeBadgeLabel.leadingAnchor.constraint(equalTo: formulaInputButton.leadingAnchor, constant: 2),
            modeBadgeLabel.trailingAnchor.constraint(equalTo: formulaInputButton.trailingAnchor, constant: -2),
            modeBadgeLabel.heightAnchor.constraint(equalToConstant: 15),

            primaryIntegralValueLabel.bottomAnchor.constraint(equalTo: formulaInputButton.bottomAnchor, constant: -1),
            primaryIntegralValueLabel.leadingAnchor.constraint(equalTo: formulaInputButton.leadingAnchor, constant: 4),
            primaryIntegralValueLabel.trailingAnchor.constraint(equalTo: formulaInputButton.trailingAnchor, constant: -2),
            primaryIntegralValueLabel.heightAnchor.constraint(equalToConstant: 22),

            expressionLabel.topAnchor.constraint(equalTo: modeBadgeLabel.bottomAnchor, constant: 1),
            expressionLabel.bottomAnchor.constraint(equalTo: primaryIntegralValueLabel.topAnchor, constant: -1),
            expressionLabel.leadingAnchor.constraint(equalTo: formulaInputButton.leadingAnchor, constant: 4),
            expressionLabel.trailingAnchor.constraint(equalTo: formulaInputButton.trailingAnchor, constant: -2),

            onDemandDetailBox.leadingAnchor.constraint(equalTo: displayPanelView.leadingAnchor, constant: 12),
            onDemandDetailBox.trailingAnchor.constraint(equalTo: displayPanelView.trailingAnchor, constant: -12),
            onDemandDetailBox.bottomAnchor.constraint(equalTo: onDemandSelector.topAnchor, constant: -4),
            onDemandBoxHeightConstraint,

            onDemandScrollView.topAnchor.constraint(equalTo: onDemandDetailBox.topAnchor),
            onDemandScrollView.leadingAnchor.constraint(equalTo: onDemandDetailBox.leadingAnchor),
            onDemandScrollView.trailingAnchor.constraint(equalTo: onDemandDetailBox.trailingAnchor),
            onDemandScrollView.bottomAnchor.constraint(equalTo: onDemandDetailBox.bottomAnchor),

            onDemandDetailLabel.topAnchor.constraint(equalTo: onDemandScrollView.topAnchor, constant: 5),
            onDemandDetailLabel.leadingAnchor.constraint(equalTo: onDemandScrollView.leadingAnchor, constant: 10),
            onDemandDetailLabel.trailingAnchor.constraint(equalTo: onDemandScrollView.trailingAnchor, constant: -10),
            onDemandDetailLabel.bottomAnchor.constraint(equalTo: onDemandScrollView.bottomAnchor, constant: -5),
            onDemandDetailLabel.widthAnchor.constraint(equalTo: onDemandScrollView.widthAnchor, constant: -20),

            onDemandSelector.leadingAnchor.constraint(equalTo: displayPanelView.leadingAnchor, constant: 12),
            onDemandSelector.trailingAnchor.constraint(equalTo: displayPanelView.trailingAnchor, constant: -12),
            onDemandSelector.bottomAnchor.constraint(equalTo: displayPanelView.bottomAnchor, constant: -5),
            onDemandSelector.heightAnchor.constraint(equalToConstant: 25),

            keypadContainer.topAnchor.constraint(equalTo: keyboardBackgroundView.topAnchor),
            keypadContainer.leadingAnchor.constraint(equalTo: keyboardBackgroundView.leadingAnchor),
            keypadContainer.trailingAnchor.constraint(equalTo: keyboardBackgroundView.trailingAnchor),
            keypadContainer.bottomAnchor.constraint(equalTo: keyboardBackgroundView.bottomAnchor),

            forceHintToast.centerXAnchor.constraint(equalTo: displayPanelView.centerXAnchor),
            forceHintToast.bottomAnchor.constraint(equalTo: displayPanelView.bottomAnchor, constant: -34),
            forceHintToast.heightAnchor.constraint(equalToConstant: 26)
        ])

        portraitConstraints = [
            displayPanelView.topAnchor.constraint(equalTo: safe.topAnchor),
            displayPanelView.leadingAnchor.constraint(equalTo: safe.leadingAnchor),
            displayPanelView.trailingAnchor.constraint(equalTo: safe.trailingAnchor),
            displayPanelView.heightAnchor.constraint(equalTo: safe.heightAnchor, multiplier: 0.35),

            keyboardBackgroundView.topAnchor.constraint(equalTo: displayPanelView.bottomAnchor, constant: 4),
            keyboardBackgroundView.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 12),
            keyboardBackgroundView.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -12),
            keyboardBackgroundView.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -4)
        ]

        landscapeConstraints = [
            displayPanelView.topAnchor.constraint(equalTo: safe.topAnchor, constant: 2),
            displayPanelView.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 6),
            displayPanelView.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -4),
            displayPanelView.widthAnchor.constraint(equalTo: safe.widthAnchor, multiplier: 0.43),

            keyboardBackgroundView.topAnchor.constraint(equalTo: safe.topAnchor, constant: 6),
            keyboardBackgroundView.leadingAnchor.constraint(equalTo: displayPanelView.trailingAnchor, constant: 10),
            keyboardBackgroundView.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -10),
            keyboardBackgroundView.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -6)
        ]
    }

    private func styleDarkSegmentedControl(_ seg: UISegmentedControl, fontSize: CGFloat) {
        seg.backgroundColor = UIColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1.0)
        seg.tintColor = UIColor(red: 0.22, green: 0.22, blue: 0.25, alpha: 1.0)
        seg.setTitleTextAttributes([
            .foregroundColor: UIColor(white: 0.62, alpha: 1.0),
            .font: UIFont.systemFont(ofSize: fontSize, weight: .medium)
        ], for: .normal)
        seg.setTitleTextAttributes([
            .foregroundColor: UIColor(red: 1.0, green: 0.584, blue: 0.0, alpha: 1.0),
            .font: UIFont.systemFont(ofSize: fontSize, weight: .bold)
        ], for: .selected)
        seg.layer.cornerRadius = 8
        seg.layer.masksToBounds = true
    }

    private func applyOrientationLayout(isLandscape: Bool) {
        NSLayoutConstraint.deactivate(portraitConstraints)
        NSLayoutConstraint.deactivate(landscapeConstraints)

        if isLandscape {
            keypadContainer.spacing = 5
            NSLayoutConstraint.activate(landscapeConstraints)
        } else {
            keypadContainer.spacing = 7
            NSLayoutConstraint.activate(portraitConstraints)
        }
        refreshOnDemandDisplayPanel(animated: false)
    }

    private func setupOriginalIntegratedCalculatorKeypad() {
        topVariableRowStack.axis = .horizontal
        topVariableRowStack.distribution = .fillEqually
        topVariableRowStack.spacing = 7
        keypadContainer.addArrangedSubview(topVariableRowStack)

        let fixedRows: [[(String, String?, String?, CalcKeyStyle)]] = [
            [("sin", "sin", "sin⁻¹", .mathFunction),
             ("cos", "cos", "cos⁻¹", .mathFunction),
             ("tan", "tan", "tan⁻¹", .mathFunction),
             ("exp", "exp", "erf",   .mathFunction),
             ("ln",  "ln",  "1/x",   .mathFunction)],

            [("^",   "xⁿ",  "^2",    .mathFunction),
             ("√",   "√x",  "|x|",   .mathFunction),
             ("(",   "(",   nil,     .mathFunction),
             (")",   ")",   nil,     .mathFunction),
             ("÷",   "÷",   nil,     .orangeOperator)],

            [("7",   "7",   nil,     .digit),
             ("8",   "8",   nil,     .digit),
             ("9",   "9",   nil,     .digit),
             ("π",   "π",   "e",     .mathFunction),
             ("×",   "×",   nil,     .orangeOperator)],

            [("4",   "4",   nil,     .digit),
             ("5",   "5",   nil,     .digit),
             ("6",   "6",   nil,     .digit),
             ("e",   "e",   nil,     .mathFunction),
             ("−",   "−",   nil,     .orangeOperator)],

            [("1",   "1",   nil,     .digit),
             ("2",   "2",   nil,     .digit),
             ("3",   "3",   nil,     .digit),
             ("±",   "⁺∕₋", nil,     .lightFunction),
             ("+",   "+",   nil,     .orangeOperator)]
        ]

        for rowItems in fixedRows {
            let rowStack = UIStackView()
            rowStack.axis = .horizontal
            rowStack.spacing = 7
            rowStack.distribution = .fillEqually

            for (token, display, sec, style) in rowItems {
                let btn = makeKeyButton(token: token, display: display, secondary: sec, style: style)
                rowStack.addArrangedSubview(btn)
            }
            keypadContainer.addArrangedSubview(rowStack)
        }

        let bottomRowStack = UIStackView()
        bottomRowStack.axis = .horizontal
        bottomRowStack.spacing = 7
        bottomRowStack.distribution = .fill

        let btn0 = makeKeyButton(token: "0", display: "0", secondary: nil, style: .digit)
        let btnDot = makeKeyButton(token: ".", display: ".", secondary: nil, style: .digit)
        let btnEq = makeKeyButton(token: "=", display: "=", secondary: "方程=", style: .orangeOperator)

        bottomRowStack.addArrangedSubview(btn0)
        bottomRowStack.addArrangedSubview(btnDot)
        bottomRowStack.addArrangedSubview(btnEq)
        keypadContainer.addArrangedSubview(bottomRowStack)

        NSLayoutConstraint.activate([
            btn0.widthAnchor.constraint(equalTo: btnDot.widthAnchor, multiplier: 2.0, constant: 7.0),
            btnEq.widthAnchor.constraint(equalTo: btnDot.widthAnchor, multiplier: 2.0, constant: 7.0)
        ])
    }

    private func rebuildTopVariableRow(for page: IntegralPageType) {
        topVariableRowStack.arrangedSubviews.forEach {
            topVariableRowStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        let currentRaw = (rawExpressions[page] ?? "").lowercased()
        let isImplicit = currentCoordMode == .implicitSurface || currentRaw.contains("=")

        var items: [(String, String?, String?, CalcKeyStyle)] = [
            ("x", "x", "x²", .variableKey)
        ]
        if page == .doubleIntegral || page == .tripleIntegral || isImplicit || currentRaw.contains("y") {
            items.append(("y", "y", "y²", .variableKey))
        }
        if page == .tripleIntegral || isImplicit || currentRaw.contains("z") {
            items.append(("z", "z", "z²", .variableKey))
        }
        items.append(("⌫", "⌫", "AC", .lightFunction))
        items.append(("AC", "AC", nil, .lightFunction))

        for (token, display, sec, style) in items {
            topVariableRowStack.addArrangedSubview(
                makeKeyButton(token: token, display: display, secondary: sec, style: style)
            )
        }
    }

    private func makeKeyButton(token: String, display: String?, secondary: String?, style: CalcKeyStyle) -> CalculatorIntegratedKeyButton {
        let keyBtn = CalculatorIntegratedKeyButton(
            primary: token,
            displaySymbol: display,
            secondaryForce: secondary,
            style: style
        )
        keyBtn.onLightTap = { [weak self] k in
            self?.handleKeyAction(key: k, isForceSecondary: false)
        }
        keyBtn.onForceDeepPress = { [weak self] secKey in
            self?.handleKeyAction(key: secKey, isForceSecondary: true)
        }
        return keyBtn
    }

    private func loadExamProblemPreset(_ preset: ExamProblemPreset) {
        currentPage = preset.pageType
        currentCoordMode = preset.coordMode
        pageSelector.selectedSegmentIndex = preset.pageType.rawValue

        switch currentCoordMode {
        case .cartesian: coordPillButton.setTitle("直角 ▾", for: .normal)
        case .polarOrSpherical: coordPillButton.setTitle("极/球 ▾", for: .normal)
        case .implicitSurface: coordPillButton.setTitle("隐式球 ▾", for: .normal)
        }

        xMinControl.rawExpression = preset.xMin
        xMaxControl.rawExpression = preset.xMax
        yMinControl.rawExpression = preset.yMin
        yMaxControl.rawExpression = preset.yMax
        zMinControl.rawExpression = preset.zMin
        zMaxControl.rawExpression = preset.zMax

        rawExpressions[preset.pageType] = preset.expression
        isAnswerMaskedForSelfTest = CalculusAppSettings.shared.isExamHintsEnabled && CalculusAppSettings.shared.isSelfTestMaskEnabled

        applyPageConfiguration(for: preset.pageType)
    }

    @objc private func coordPillTapped() {
        TactileFeedbackManager.shared.playModifierTap()
        let nextRaw = (currentCoordMode.rawValue + 1) % 3
        currentCoordMode = CoordinateSystemMode(rawValue: nextRaw) ?? .cartesian

        switch currentCoordMode {
        case .cartesian:
            coordPillButton.setTitle("直角 ▾", for: .normal)
        case .polarOrSpherical:
            coordPillButton.setTitle("极/球 ▾", for: .normal)
        case .implicitSurface:
            coordPillButton.setTitle("隐式球 ▾", for: .normal)
            rawExpressions[currentPage] = "x^2+y^2+z^2=1"
            expressionLabel.text = NaturalMathFormatter.prettifyForDisplay("x^2+y^2+z^2=1")
        }
        rebuildTopVariableRow(for: currentPage)
        recalculateAll()
    }

    @objc private func onDemandCategoryChanged() {
        TactileFeedbackManager.shared.playModifierTap()
        currentDisplayCategory = OnDemandDisplayCategory(rawValue: onDemandSelector.selectedSegmentIndex) ?? .primaryOnly
        refreshOnDemandDisplayPanel(animated: true)
    }

    private func refreshOnDemandDisplayPanel(animated: Bool) {
        guard let res = latestAnalysis else { return }
        let isLandscape = (view.bounds.width > view.bounds.height)
        let hintsOn = CalculusAppSettings.shared.isExamHintsEnabled
        let expandedHeight: CGFloat = isLandscape ? 82.0 : 48.0

        switch currentDisplayCategory {
        case .primaryOnly:
            onDemandDetailLabel.text = ""
            onDemandBoxHeightConstraint.constant = 0
        case .derivAndGeometry:
            onDemandDetailLabel.text = res.derivDetailText
            onDemandBoxHeightConstraint.constant = expandedHeight
        case .scoringSteps:
            if isAnswerMaskedForSelfTest {
                onDemandDetailLabel.text = "🎯 考场自测遮挡中：请先自己思考原函数，再点击上方橙色文字揭晓步骤！"
            } else {
                onDemandDetailLabel.text = res.scoringStepsText
            }
            onDemandBoxHeightConstraint.constant = expandedHeight
        case .limitAndTangent:
            onDemandDetailLabel.text = hintsOn ? res.examIntuitionText : res.limitAndTangentText
            onDemandBoxHeightConstraint.constant = expandedHeight
        case .trapsAndFit:
            onDemandDetailLabel.text = hintsOn ? res.trapAndFitText : res.pureFitText
            onDemandBoxHeightConstraint.constant = expandedHeight
        }

        let isDetailOpen = (currentDisplayCategory != .primaryOnly)
        if isLandscape {
            expressionLabel.font = UIFont.systemFont(ofSize: (isDetailOpen || isBoundsDrawerExpanded) ? 22 : 28, weight: .light)
        } else {
            if isDetailOpen && isBoundsDrawerExpanded {
                expressionLabel.font = UIFont.systemFont(ofSize: 20, weight: .regular)
            } else if isDetailOpen || isBoundsDrawerExpanded {
                expressionLabel.font = UIFont.systemFont(ofSize: 24, weight: .light)
            } else {
                expressionLabel.font = UIFont.systemFont(ofSize: 34, weight: .light)
            }
        }

        if animated {
            UIView.animate(withDuration: 0.18) {
                self.view.layoutIfNeeded()
            }
        }
    }

    @objc private func formulaBoxTapped() {
        TactileFeedbackManager.shared.playKeyTap()
        setActiveBoundsControl(nil)
        if isAnswerMaskedForSelfTest {
            isAnswerMaskedForSelfTest = false
            TactileFeedbackManager.shared.playModifierTap()
            recalculateAll()
        }
    }

    @objc private func boundsControlTapped(_ sender: BoundsInputButton) {
        TactileFeedbackManager.shared.playKeyTap()
        setActiveBoundsControl(sender)
    }

    private func setActiveBoundsControl(_ control: BoundsInputButton?) {
        let all = [xMinControl, xMaxControl, x0Control, yMinControl, yMaxControl, y0Control, zMinControl, zMaxControl]
        for c in all {
            c.isActiveInput = (c === control)
            if c === control {
                c.shouldOverwriteOnNextChar = true
            }
        }
        activeBoundsControl = control
        expressionLabel.textColor = (control == nil) ? .white : UIColor(white: 0.55, alpha: 1.0)
    }

    @objc private func toggleBoundsDrawerTapped() {
        TactileFeedbackManager.shared.playModifierTap()
        isBoundsDrawerExpanded.toggle()
        if !isBoundsDrawerExpanded {
            setActiveBoundsControl(nil)
            recalculateAll()
        }
        updateBoundsDrawerLayout(animated: true)
        refreshOnDemandDisplayPanel(animated: true)
    }

    private func updateBoundsDrawerLayout(animated: Bool) {
        let targetHeight: CGFloat
        let xRangeTitle = "[\(NaturalMathFormatter.prettifyForDisplay(xMinControl.rawExpression)),\(NaturalMathFormatter.prettifyForDisplay(xMaxControl.rawExpression))]"
        if !isBoundsDrawerExpanded {
            targetHeight = 0
            boundsToggleHeader.setTitle("\(xRangeTitle) ▾", for: .normal)
            boundsToggleHeader.setTitleColor(UIColor(white: 0.86, alpha: 1.0), for: .normal)
        } else {
            targetHeight = (currentPage == .singleIntegral) ? 30 : 62
            boundsToggleHeader.setTitle("收起 ▲", for: .normal)
            boundsToggleHeader.setTitleColor(UIColor(red: 1.0, green: 0.584, blue: 0.0, alpha: 1.0), for: .normal)
        }
        boundsDrawerHeightConstraint.constant = targetHeight

        if animated {
            UIView.animate(withDuration: 0.20, delay: 0, options: [.curveEaseInOut], animations: {
                self.boundsDrawerContainer.alpha = self.isBoundsDrawerExpanded ? 1.0 : 0.0
                self.view.layoutIfNeeded()
            }, completion: nil)
        } else {
            boundsDrawerContainer.alpha = isBoundsDrawerExpanded ? 1.0 : 0.0
        }
    }

    @objc private func pageSegmentChanged() {
        TactileFeedbackManager.shared.playModifierTap()
        let nextPage = IntegralPageType(rawValue: pageSelector.selectedSegmentIndex) ?? .singleIntegral
        applyPageConfiguration(for: nextPage)
    }

    private func applyPageConfiguration(for page: IntegralPageType) {
        currentPage = page
        let raw = rawExpressions[page] ?? "2x"
        expressionLabel.text = NaturalMathFormatter.prettifyForDisplay(raw)
        setActiveBoundsControl(nil)
        rebuildTopVariableRow(for: page)

        boundsRow2Stack.arrangedSubviews.forEach {
            boundsRow2Stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        switch page {
        case .singleIntegral:
            x0Control.isHidden = false
            boundsRow2Stack.isHidden = true

        case .doubleIntegral:
            x0Control.isHidden = false
            boundsRow2Stack.isHidden = false
            boundsRow2Stack.addArrangedSubview(yMinControl)
            boundsRow2Stack.addArrangedSubview(yMaxControl)
            boundsRow2Stack.addArrangedSubview(y0Control)

        case .tripleIntegral:
            x0Control.isHidden = true
            boundsRow2Stack.isHidden = false
            boundsRow2Stack.addArrangedSubview(yMinControl)
            boundsRow2Stack.addArrangedSubview(yMaxControl)
            boundsRow2Stack.addArrangedSubview(zMinControl)
            boundsRow2Stack.addArrangedSubview(zMaxControl)
        }

        updateBoundsDrawerLayout(animated: false)
        recalculateAll()
    }

    private func register3DTouchPeekAndPop() {
        if traitCollection.forceTouchCapability == .available {
            registerForPreviewing(with: self, sourceView: formulaInputButton)
        }
    }

    func previewingContext(_ previewingContext: UIViewControllerPreviewing, viewControllerForLocation location: CGPoint) -> UIViewController? {
        TactileFeedbackManager.shared.play3DTouchPeek()
        let params = currentParameters()
        let analysis = recalculateAll()
        let graphVC = Calculus3DGraphViewController(parameters: params, analysis: analysis)
        graphVC.preferredContentSize = CGSize(width: 0.0, height: 420.0)
        return graphVC
    }

    func previewingContext(_ previewingContext: UIViewControllerPreviewing, commit viewControllerToCommit: UIViewController) {
        TactileFeedbackManager.shared.play3DTouchDeepPop()
        let nav = UINavigationController(rootViewController: viewControllerToCommit)
        nav.modalPresentationStyle = .fullScreen
        present(nav, animated: true, completion: nil)
    }

    private func showForceToast(_ text: String) {
        forceHintToast.text = "  3D Touch 输入: \(text)  "
        forceHintToast.alpha = 1.0
        UIView.animate(withDuration: 0.35, delay: 0.65, options: [.curveEaseOut], animations: {
            self.forceHintToast.alpha = 0.0
        }, completion: nil)
    }

    private func handleKeyAction(key: String, isForceSecondary: Bool) {
        if let boundsCtrl = activeBoundsControl {
            switch key {
            case "=":
                boundsCtrl.shouldOverwriteOnNextChar = false
                setActiveBoundsControl(nil)
                updateBoundsDrawerLayout(animated: false)
                recalculateAll()
            case "AC":
                boundsCtrl.rawExpression = "0"
                boundsCtrl.shouldOverwriteOnNextChar = true
            case "⌫":
                let cur = boundsCtrl.rawExpression
                if cur.count <= 1 {
                    boundsCtrl.rawExpression = "0"
                    boundsCtrl.shouldOverwriteOnNextChar = true
                } else {
                    boundsCtrl.rawExpression = String(cur.dropLast())
                }
            case "±":
                let clean = boundsCtrl.rawExpression.replacingOccurrences(of: "−", with: "-")
                if clean.hasPrefix("-") {
                    boundsCtrl.rawExpression = String(clean.dropFirst())
                } else {
                    boundsCtrl.rawExpression = "-" + clean
                }
                boundsCtrl.shouldOverwriteOnNextChar = false
            default:
                let allowedInBounds = ["0","1","2","3","4","5","6","7","8","9",".","π","e","÷","×","−","+"]
                if allowedInBounds.contains(key) {
                    let mapped = (key == "÷") ? "/" : key
                    if boundsCtrl.shouldOverwriteOnNextChar || boundsCtrl.rawExpression == "0" {
                        if ["/", "÷", "×", "+"].contains(mapped) {
                            boundsCtrl.rawExpression += mapped
                        } else {
                            boundsCtrl.rawExpression = (mapped == ".") ? "0." : mapped
                        }
                        boundsCtrl.shouldOverwriteOnNextChar = false
                    } else {
                        boundsCtrl.rawExpression += mapped
                    }
                }
            }
            return
        }

        var raw = rawExpressions[currentPage] ?? ""

        if isForceSecondary {
            showForceToast(key)
            switch key {
            case "x²": raw += "x^2"
            case "y²": raw += "y^2"
            case "z²": raw += "z^2"
            case "^2": raw += "^2"
            case "sin⁻¹": raw += "asin("
            case "cos⁻¹": raw += "acos("
            case "tan⁻¹": raw += "atan("
            case "|x|": raw += "abs("
            case "erf": raw += "erf("
            case "1/x": raw += "1/("
            case "e": raw += "e"
            case "方程=":
                raw += "="
                rawExpressions[currentPage] = raw
                rebuildTopVariableRow(for: currentPage)
            case "AC":
                raw = ""
                primaryIntegralValueLabel.text = ""
            default: raw += key
            }
            rawExpressions[currentPage] = raw
            expressionLabel.text = NaturalMathFormatter.prettifyForDisplay(raw)
            recalculateAll()
            return
        }

        switch key {
        case "AC":
            raw = ""
            primaryIntegralValueLabel.text = ""
        case "⌫":
            if !raw.isEmpty {
                raw = String(raw.dropLast())
            }
        case "±":
            let clean = raw.replacingOccurrences(of: "−", with: "-")
            raw = clean.hasPrefix("-") ? String(clean.dropFirst()) : "-" + clean
        case "=":
            raw = NaturalMathFormatter.autoBalanceParentheses(raw)
            rawExpressions[currentPage] = raw
            expressionLabel.text = NaturalMathFormatter.prettifyForDisplay(raw)
            rebuildTopVariableRow(for: currentPage)
            isAnswerMaskedForSelfTest = CalculusAppSettings.shared.isExamHintsEnabled && CalculusAppSettings.shared.isSelfTestMaskEnabled
            recalculateAll()
            return
        case "÷":
            raw += "/"
        case "sin", "cos", "tan", "exp", "ln", "√":
            let fn = (key == "√") ? "√(" : (key + "(")
            raw += fn
        default:
            raw += key
        }

        rawExpressions[currentPage] = raw
        expressionLabel.text = NaturalMathFormatter.prettifyForDisplay(raw)
    }

    func currentParameters() -> CalculusInputParameters {
        let expr = rawExpressions[currentPage] ?? "2x"
        let activeBoundsRaw: [String]
        switch currentPage {
        case .singleIntegral:
            activeBoundsRaw = [xMinControl.rawExpression, xMaxControl.rawExpression]
        case .doubleIntegral:
            activeBoundsRaw = [xMinControl.rawExpression, xMaxControl.rawExpression, yMinControl.rawExpression, yMaxControl.rawExpression]
        case .tripleIntegral:
            activeBoundsRaw = [xMinControl.rawExpression, xMaxControl.rawExpression, yMinControl.rawExpression, yMaxControl.rawExpression, zMinControl.rawExpression, zMaxControl.rawExpression]
        }
        let preferFraction = !ExactMathValueFormatter.hasExplicitDecimalInInput(expression: expr, boundsRawStrings: activeBoundsRaw)

        return CalculusInputParameters(
            pageType: currentPage,
            coordMode: currentCoordMode,
            expression: expr,
            xMin: xMinControl.numericValue,
            xMax: xMaxControl.numericValue,
            yMin: yMinControl.numericValue,
            yMax: yMaxControl.numericValue,
            zMin: zMinControl.numericValue,
            zMax: zMaxControl.numericValue,
            x0: x0Control.numericValue,
            y0: y0Control.numericValue,
            preferFraction: preferFraction
        )
    }

    @discardableResult
    func recalculateAll() -> FullCalculusAnalysis {
        let params = currentParameters()
        let res = NumericalCalculusEngine.analyze(params: params)
        latestAnalysis = res

        let hintsOn = CalculusAppSettings.shared.isExamHintsEnabled
        if hintsOn {
            modeBadgeLabel.text = res.oneLineCoachHint
            modeBadgeLabel.textColor = UIColor(red: 1.0, green: 0.72, blue: 0.28, alpha: 0.95)
        } else {
            let cName: String
            switch currentCoordMode {
            case .cartesian: cName = "直角坐标"
            case .polarOrSpherical: cName = "极/球坐标"
            case .implicitSurface: cName = "隐式曲面"
            }
            modeBadgeLabel.text = "Rad · \(cName) · 重压算式看图像"
            modeBadgeLabel.textColor = UIColor(white: 0.52, alpha: 1.0)
        }

        if hintsOn && isAnswerMaskedForSelfTest {
            primaryIntegralValueLabel.text = "🎯 思考破题法... (点此揭晓答案)"
        } else {
            primaryIntegralValueLabel.text = res.primaryIntegralResultText
        }
        refreshOnDemandDisplayPanel(animated: false)
        return res
    }
}

// MARK: - 14. 专属几何可视化页 (支持自由平移图像、全区域可拉伸坐标轴、防穿模安全相机与三档透视透明功能)

final class Calculus3DGraphViewController: UIViewController {

    private enum SurfaceTransparencyMode: Int {
        case semiTransparent = 0   // 默认半透 (52%)：既看清立体曲面又清晰透视内部坐标轴
        case highTransparent = 1   // 高透视 (25%)：薄纱模式，重点突显内部坐标轴与截面
        case solidOpaque = 2       // 实心 (95%)：不透明立体表面

        var opacity: CGFloat {
            switch self {
            case .semiTransparent: return 0.52
            case .highTransparent: return 0.25
            case .solidOpaque:     return 0.95
            }
        }

        var buttonTitle: String {
            switch self {
            case .semiTransparent: return "半透"
            case .highTransparent: return "高透"
            case .solidOpaque:     return "实心"
            }
        }
    }

    private var params: CalculusInputParameters
    private var analysis: FullCalculusAnalysis

    private let sceneView = SCNView()
    private let plot2DView = Cartesian2DPlotView()
    private let geometryContainerNode = SCNNode()
    private var axesContainerNode: SCNNode?
    private var contourSliceNode: SCNNode?
    private var revolutionDiskNode: SCNNode?
    private let mainCameraNode = SCNNode()

    // 自研 3D 自由平移 + 轨道旋转 + 防穿模相机状态
    private var cameraTarget = SCNVector3(0, 0, 0)
    private var cameraAzimuth: Float = Float.pi / 4.0
    private var cameraElevation: Float = 0.58
    private var cameraDistance: Float = 11.0
    private var objectSurfaceRadius: Float = 2.5
    private var baseAxisRadius: Float = 4.5
    private var axisStretchMultiplier: Float = 1.0

    private var isPanModeEnabled = false
    private var transparencyMode: SurfaceTransparencyMode = .semiTransparent
    private var isAutoSpinning = false
    private var showReferenceGrid = true

    private var lastPanTranslation: CGPoint = .zero
    private var pinchStartDistance: Float = 11.0

    private let summaryCard = UIView()
    private let summaryFormulaLabel = UILabel()
    private let summaryMetricsLabel = UILabel()
    private var modeSegmentedControl: UISegmentedControl!

    private let interactionModeBannerButton = UIButton(type: .system)

    private let contourBar = UIView()
    private let axisStretchLabel = UILabel()
    private let axisStretchSlider = UISlider()
    private let contourLabel = UILabel()
    private let contourSlider = UISlider()

    private let floatingToolbar = UIStackView()
    private let panModeButton = UIButton(type: .system)
    private let transparencyButton = UIButton(type: .system)
    private let spinButton = UIButton(type: .system)
    private let gridButton = UIButton(type: .system)
    private let resetButton = UIButton(type: .system)

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .allButUpsideDown
    }

    init(parameters: CalculusInputParameters, analysis: FullCalculusAnalysis) {
        self.params = parameters
        self.analysis = analysis
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        setupNavigationBar()
        setupCanvasViewsOnce()
        setupSummaryCard()
        setupInteractionBanner()
        setupBottomSlidersBar()
        setupFloatingButtons()
        refreshVisualization(resetCameraState: true)
    }

    private func setupNavigationBar() {
        if analysis.isImplicitEquation {
            title = "隐式曲面 3D 直观图解"
        } else {
            switch params.pageType {
            case .singleIntegral: title = "定积分与微元圆盘直观图解"
            case .doubleIntegral: title = "二重积分与切面直观图解"
            case .tripleIntegral: title = "三重积分与体素直观图解"
            }
        }

        navigationController?.navigationBar.barTintColor = UIColor(red: 0.08, green: 0.08, blue: 0.09, alpha: 1.0)
        navigationController?.navigationBar.isTranslucent = false
        navigationController?.navigationBar.tintColor = UIColor(red: 1.0, green: 0.584, blue: 0.0, alpha: 1.0)
        navigationController?.navigationBar.titleTextAttributes = [
            .foregroundColor: UIColor.white,
            .font: UIFont.systemFont(ofSize: 16.5, weight: .semibold)
        ]

        let backItem = UIBarButtonItem(title: "完成", style: .done, target: self, action: #selector(doneTapped))
        navigationItem.leftBarButtonItem = backItem
    }

    private func setupCanvasViewsOnce() {
        let scene = SCNScene()
        sceneView.scene = scene
        sceneView.backgroundColor = UIColor(red: 0.05, green: 0.05, blue: 0.06, alpha: 1.0)
        // 关闭系统默认相机控制，改由自研防穿模 + 自由平移手势控制器完全接管
        sceneView.allowsCameraControl = false
        sceneView.autoenablesDefaultLighting = false
        sceneView.antialiasingMode = .multisampling4X
        sceneView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(sceneView)

        let ambient = SCNNode()
        ambient.light = SCNLight(); ambient.light?.type = .ambient
        ambient.light?.color = UIColor(white: 0.76, alpha: 1.0)
        scene.rootNode.addChildNode(ambient)

        let dir1 = SCNNode()
        dir1.light = SCNLight(); dir1.light?.type = .directional
        dir1.light?.color = UIColor(white: 0.92, alpha: 1.0)
        dir1.position = SCNVector3(25, 35, 30); dir1.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(dir1)

        let dir2 = SCNNode()
        dir2.light = SCNLight(); dir2.light?.type = .directional
        dir2.light?.color = UIColor(white: 0.45, alpha: 1.0)
        dir2.position = SCNVector3(-25, -30, -25); dir2.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(dir2)

        let cam = SCNCamera()
        cam.fieldOfView = 52.0
        cam.zNear = 0.1
        cam.zFar = 2000.0
        mainCameraNode.camera = cam
        scene.rootNode.addChildNode(mainCameraNode)
        sceneView.pointOfView = mainCameraNode

        scene.rootNode.addChildNode(geometryContainerNode)

        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handle3DPan(_:)))
        panGesture.minimumNumberOfTouches = 1
        panGesture.maximumNumberOfTouches = 2
        sceneView.addGestureRecognizer(panGesture)

        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handle3DPinch(_:)))
        sceneView.addGestureRecognizer(pinchGesture)

        plot2DView.translatesAutoresizingMaskIntoConstraints = false
        plot2DView.isHidden = true
        view.addSubview(plot2DView)

        NSLayoutConstraint.activate([
            sceneView.topAnchor.constraint(equalTo: view.topAnchor),
            sceneView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sceneView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            sceneView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            plot2DView.topAnchor.constraint(equalTo: view.topAnchor),
            plot2DView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            plot2DView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            plot2DView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setupSummaryCard() {
        let safe = view.safeAreaLayoutGuide

        summaryCard.backgroundColor = UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 0.94)
        summaryCard.layer.cornerRadius = 12
        summaryCard.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(summaryCard)

        let items: [String]
        if analysis.isImplicitEquation {
            items = ["3D 隐式曲面/球体", "∂F 法向与切平面"]
        } else {
            switch params.pageType {
            case .singleIntegral:
                items = ["2D 正负面积染色图", "3D 旋转体与黄金微元圆盘"]
            case .doubleIntegral:
                items = ["∬ 积分体积柱微元", "∂f 偏导切平面", "3D 曲面与等值线"]
            case .tripleIntegral:
                items = ["∭ 3D 体素密度云", "3D 正交三截面热力图"]
            }
        }

        summaryFormulaLabel.text = "\(NaturalMathFormatter.prettifyForDisplay(params.expression))   \(analysis.primaryIntegralResultText)"
        summaryFormulaLabel.font = UIFont.systemFont(ofSize: 14, weight: .bold)
        summaryFormulaLabel.textColor = .white
        summaryFormulaLabel.translatesAutoresizingMaskIntoConstraints = false
        summaryCard.addSubview(summaryFormulaLabel)

        summaryMetricsLabel.text = CalculusAppSettings.shared.isExamHintsEnabled ? analysis.oneLineCoachHint : analysis.summaryBanner
        summaryMetricsLabel.font = UIFont.systemFont(ofSize: 11, weight: .medium)
        summaryMetricsLabel.textColor = UIColor(red: 1.0, green: 0.70, blue: 0.25, alpha: 1.0)
        summaryMetricsLabel.translatesAutoresizingMaskIntoConstraints = false
        summaryCard.addSubview(summaryMetricsLabel)

        modeSegmentedControl = UISegmentedControl(items: items)
        modeSegmentedControl.selectedSegmentIndex = 0
        modeSegmentedControl.backgroundColor = UIColor(red: 0.16, green: 0.16, blue: 0.18, alpha: 1.0)
        modeSegmentedControl.tintColor = UIColor(red: 1.0, green: 0.584, blue: 0.0, alpha: 1.0)
        modeSegmentedControl.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .normal)
        modeSegmentedControl.setTitleTextAttributes([.foregroundColor: UIColor.black], for: .selected)
        modeSegmentedControl.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
        modeSegmentedControl.translatesAutoresizingMaskIntoConstraints = false
        summaryCard.addSubview(modeSegmentedControl)

        NSLayoutConstraint.activate([
            summaryCard.topAnchor.constraint(equalTo: safe.topAnchor, constant: 8),
            summaryCard.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 12),
            summaryCard.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -12),
            summaryCard.heightAnchor.constraint(equalToConstant: 78),

            summaryFormulaLabel.topAnchor.constraint(equalTo: summaryCard.topAnchor, constant: 6),
            summaryFormulaLabel.leadingAnchor.constraint(equalTo: summaryCard.leadingAnchor, constant: 10),
            summaryFormulaLabel.trailingAnchor.constraint(equalTo: summaryCard.trailingAnchor, constant: -10),

            summaryMetricsLabel.topAnchor.constraint(equalTo: summaryFormulaLabel.bottomAnchor, constant: 2),
            summaryMetricsLabel.leadingAnchor.constraint(equalTo: summaryCard.leadingAnchor, constant: 10),
            summaryMetricsLabel.trailingAnchor.constraint(equalTo: summaryCard.trailingAnchor, constant: -10),

            modeSegmentedControl.bottomAnchor.constraint(equalTo: summaryCard.bottomAnchor, constant: -6),
            modeSegmentedControl.leadingAnchor.constraint(equalTo: summaryCard.leadingAnchor, constant: 10),
            modeSegmentedControl.trailingAnchor.constraint(equalTo: summaryCard.trailingAnchor, constant: -10),
            modeSegmentedControl.heightAnchor.constraint(equalToConstant: 26)
        ])
    }

    private func setupInteractionBanner() {
        let safe = view.safeAreaLayoutGuide
        interactionModeBannerButton.backgroundColor = UIColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 0.88)
        interactionModeBannerButton.layer.cornerRadius = 12
        interactionModeBannerButton.layer.borderWidth = 0.8
        interactionModeBannerButton.layer.borderColor = UIColor(red: 1.0, green: 0.584, blue: 0.0, alpha: 0.45).cgColor
        interactionModeBannerButton.titleLabel?.font = UIFont.systemFont(ofSize: 11.0, weight: .semibold)
        interactionModeBannerButton.contentEdgeInsets = UIEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)
        interactionModeBannerButton.addTarget(self, action: #selector(togglePanModeTapped), for: .touchUpInside)
        interactionModeBannerButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(interactionModeBannerButton)

        NSLayoutConstraint.activate([
            interactionModeBannerButton.topAnchor.constraint(equalTo: summaryCard.bottomAnchor, constant: 6),
            interactionModeBannerButton.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 12),
            interactionModeBannerButton.heightAnchor.constraint(equalToConstant: 24)
        ])
        updatePanModeUI()
    }

    private func setupBottomSlidersBar() {
        let safe = view.safeAreaLayoutGuide

        contourBar.backgroundColor = UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 0.94)
        contourBar.layer.cornerRadius = 12
        contourBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contourBar)

        axisStretchLabel.text = "坐标轴范围 ±6.5 (拉伸 1.0x)"
        axisStretchLabel.font = UIFont.systemFont(ofSize: 10.5, weight: .semibold)
        axisStretchLabel.textColor = UIColor(red: 0.45, green: 0.82, blue: 1.0, alpha: 1.0)
        axisStretchLabel.translatesAutoresizingMaskIntoConstraints = false
        contourBar.addSubview(axisStretchLabel)

        axisStretchSlider.minimumValue = 0.6
        axisStretchSlider.maximumValue = 2.8
        axisStretchSlider.value = 1.0
        axisStretchSlider.tintColor = UIColor(red: 0.20, green: 0.65, blue: 1.0, alpha: 1.0)
        axisStretchSlider.addTarget(self, action: #selector(axisStretchSliderChanged(_:)), for: .valueChanged)
        axisStretchSlider.translatesAutoresizingMaskIntoConstraints = false
        contourBar.addSubview(axisStretchSlider)

        contourLabel.text = "截面与等值线 z = 0.00"
        contourLabel.font = UIFont.systemFont(ofSize: 10.5, weight: .semibold)
        contourLabel.textColor = .white
        contourLabel.translatesAutoresizingMaskIntoConstraints = false
        contourBar.addSubview(contourLabel)

        contourSlider.minimumValue = -2.5
        contourSlider.maximumValue = 2.5
        contourSlider.value = 0.0
        contourSlider.tintColor = UIColor(red: 1.0, green: 0.584, blue: 0.0, alpha: 1.0)
        contourSlider.addTarget(self, action: #selector(contourSliderChanged(_:)), for: .valueChanged)
        contourSlider.translatesAutoresizingMaskIntoConstraints = false
        contourBar.addSubview(contourSlider)

        NSLayoutConstraint.activate([
            contourBar.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 12),
            contourBar.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -84),
            contourBar.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -14),
            contourBar.heightAnchor.constraint(equalToConstant: 74),

            axisStretchLabel.topAnchor.constraint(equalTo: contourBar.topAnchor, constant: 8),
            axisStretchLabel.leadingAnchor.constraint(equalTo: contourBar.leadingAnchor, constant: 10),
            axisStretchLabel.widthAnchor.constraint(equalToConstant: 152),

            axisStretchSlider.centerYAnchor.constraint(equalTo: axisStretchLabel.centerYAnchor),
            axisStretchSlider.leadingAnchor.constraint(equalTo: axisStretchLabel.trailingAnchor, constant: 6),
            axisStretchSlider.trailingAnchor.constraint(equalTo: contourBar.trailingAnchor, constant: -10),

            contourLabel.bottomAnchor.constraint(equalTo: contourBar.bottomAnchor, constant: -10),
            contourLabel.leadingAnchor.constraint(equalTo: contourBar.leadingAnchor, constant: 10),
            contourLabel.widthAnchor.constraint(equalToConstant: 152),

            contourSlider.centerYAnchor.constraint(equalTo: contourLabel.centerYAnchor),
            contourSlider.leadingAnchor.constraint(equalTo: contourLabel.trailingAnchor, constant: 6),
            contourSlider.trailingAnchor.constraint(equalTo: contourBar.trailingAnchor, constant: -10)
        ])
    }

    private func setupFloatingButtons() {
        let safe = view.safeAreaLayoutGuide

        floatingToolbar.axis = .vertical
        floatingToolbar.spacing = 6
        floatingToolbar.distribution = .fillEqually
        floatingToolbar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(floatingToolbar)

        let configs: [(UIButton, String, Selector)] = [
            (panModeButton, "平移", #selector(togglePanModeTapped)),
            (transparencyButton, transparencyMode.buttonTitle, #selector(toggleTransparencyTapped)),
            (spinButton, "旋转", #selector(toggleSpinTapped)),
            (gridButton, "网格", #selector(toggleGridTapped)),
            (resetButton, "复位", #selector(resetCameraTapped))
        ]

        for (btn, title, sel) in configs {
            btn.setTitle(title, for: .normal)
            btn.titleLabel?.font = UIFont.systemFont(ofSize: 12.5, weight: .semibold)
            btn.setTitleColor(UIColor(red: 1.0, green: 0.584, blue: 0.0, alpha: 1.0), for: .normal)
            btn.backgroundColor = UIColor(red: 0.14, green: 0.14, blue: 0.16, alpha: 0.94)
            btn.layer.cornerRadius = 16
            btn.contentEdgeInsets = UIEdgeInsets(top: 6, left: 11, bottom: 6, right: 11)
            btn.addTarget(self, action: sel, for: .touchUpInside)
            floatingToolbar.addArrangedSubview(btn)
        }

        NSLayoutConstraint.activate([
            floatingToolbar.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -12),
            floatingToolbar.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -14)
        ])
    }

    private func updatePanModeUI() {
        if isPanModeEnabled {
            panModeButton.setTitle("平移中", for: .normal)
            panModeButton.backgroundColor = UIColor(red: 1.0, green: 0.584, blue: 0.0, alpha: 1.0)
            panModeButton.setTitleColor(.black, for: .normal)
            interactionModeBannerButton.setTitle("✋ 当前：单指自由平移图像 (点此切回旋转)", for: .normal)
            interactionModeBannerButton.setTitleColor(UIColor(red: 1.0, green: 0.65, blue: 0.15, alpha: 1.0), for: .normal)
        } else {
            panModeButton.setTitle("平移", for: .normal)
            panModeButton.backgroundColor = UIColor(red: 0.14, green: 0.14, blue: 0.16, alpha: 0.94)
            panModeButton.setTitleColor(UIColor(red: 1.0, green: 0.584, blue: 0.0, alpha: 1.0), for: .normal)
            interactionModeBannerButton.setTitle("🔄 单指旋转 · 双指平移 · 捏合防穿模缩放 (点此切单指平移)", for: .normal)
            interactionModeBannerButton.setTitleColor(UIColor(white: 0.86, alpha: 1.0), for: .normal)
        }
    }

    // MARK: - 防穿模 + 自由平移 + 轨道旋转 3D 相机核心算法

    private var minSafeCameraDistance: Float {
        // 严格保证相机距离不小于物体外表面半径的 1.22 倍，绝不进入球体/曲面内部
        return max(2.2, objectSurfaceRadius * 1.22)
    }

    private var maxAllowedCameraDistance: Float {
        return max(120.0, baseAxisRadius * 12.0)
    }

    private func applyCameraTransform(animated: Bool = false) {
        cameraElevation = max(-Float.pi * 0.46, min(Float.pi * 0.46, cameraElevation))
        cameraDistance = max(minSafeCameraDistance, min(maxAllowedCameraDistance, cameraDistance))

        let cosE = cos(cameraElevation)
        let sinE = sin(cameraElevation)
        let cosA = cos(cameraAzimuth)
        let sinA = sin(cameraAzimuth)

        var camX = cameraTarget.x + cameraDistance * cosE * sinA
        var camY = cameraTarget.y + cameraDistance * sinE
        var camZ = cameraTarget.z + cameraDistance * cosE * cosA

        // 二重防穿模球面硬保护：即便用户大幅平移了 cameraTarget，也绝不允许相机世界坐标进入物体外表面半径 1.18 倍以内
        let distFromOrigin = sqrt(camX * camX + camY * camY + camZ * camZ)
        let hardShellRadius = max(1.8, objectSurfaceRadius * 1.18)
        if distFromOrigin < hardShellRadius {
            if distFromOrigin > 1e-4 {
                let pushScale = hardShellRadius / distFromOrigin
                camX *= pushScale
                camY *= pushScale
                camZ *= pushScale
            } else {
                camX = hardShellRadius * 0.6
                camY = hardShellRadius * 0.6
                camZ = hardShellRadius * 0.6
            }
        }

        let finalPos = SCNVector3(camX, camY, camZ)
        mainCameraNode.camera?.zNear = Double(max(0.05, objectSurfaceRadius * 0.03))
        mainCameraNode.camera?.zFar = Double(max(400.0, cameraDistance * 10.0))

        if animated {
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.35
            mainCameraNode.position = finalPos
            mainCameraNode.look(at: cameraTarget, up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
            SCNTransaction.commit()
        } else {
            mainCameraNode.position = finalPos
            mainCameraNode.look(at: cameraTarget, up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
        }
    }

    @objc private func handle3DPan(_ gesture: UIPanGestureRecognizer) {
        let pt = gesture.translation(in: sceneView)
        if gesture.state == .began {
            lastPanTranslation = .zero
        }
        let dx = Float(pt.x - lastPanTranslation.x)
        let dy = Float(pt.y - lastPanTranslation.y)
        lastPanTranslation = pt

        let shouldPanImage = isPanModeEnabled || (gesture.numberOfTouches >= 2)
        if shouldPanImage {
            // 沿当前相机屏幕平面的右向量 (Right) 与上向量 (Up) 自由平移整个 3D 图像
            let panScale = cameraDistance * 0.0021
            let cosA = cos(cameraAzimuth)
            let sinA = sin(cameraAzimuth)
            let sinE = sin(cameraElevation)
            let cosE = cos(cameraElevation)

            let rightX = cosA
            let rightY: Float = 0.0
            let rightZ = -sinA

            let upX = -sinE * sinA
            let upY = cosE
            let upZ = -sinE * cosA

            cameraTarget.x += (-dx * rightX + dy * upX) * panScale
            cameraTarget.y += (-dx * rightY + dy * upY) * panScale
            cameraTarget.z += (-dx * rightZ + dy * upZ) * panScale

            let maxPanBound = baseAxisRadius * axisStretchMultiplier * 2.5
            cameraTarget.x = max(-maxPanBound, min(maxPanBound, cameraTarget.x))
            cameraTarget.y = max(-maxPanBound, min(maxPanBound, cameraTarget.y))
            cameraTarget.z = max(-maxPanBound, min(maxPanBound, cameraTarget.z))
        } else {
            // 围绕当前观察中心 cameraTarget 旋转视角
            cameraAzimuth -= dx * 0.0085
            cameraElevation += dy * 0.0075
        }
        applyCameraTransform(animated: false)
    }

    @objc private func handle3DPinch(_ gesture: UIPinchGestureRecognizer) {
        if gesture.state == .began {
            pinchStartDistance = cameraDistance
        }
        let scale = Float(max(0.15, min(8.0, gesture.scale)))
        let proposedDistance = pinchStartDistance / scale
        // 当触达防穿模最小安全距离时给出轻微震动反馈，提示已贴近物体外表面
        if proposedDistance < minSafeCameraDistance && cameraDistance > minSafeCameraDistance * 1.01 {
            TactileFeedbackManager.shared.playAxisSnapDetent()
        }
        cameraDistance = max(minSafeCameraDistance, min(maxAllowedCameraDistance, proposedDistance))
        applyCameraTransform(animated: false)
    }

    // MARK: - 坐标轴实时拉伸与截面滑块响应

    @objc private func axisStretchSliderChanged(_ sender: UISlider) {
        let mult = sender.value
        if abs(mult - 1.0) < 0.03 || abs(mult - 1.5) < 0.03 || abs(mult - 2.0) < 0.03 {
            TactileFeedbackManager.shared.playAxisSnapDetent()
        }
        axisStretchMultiplier = mult
        let stretchedAxisLen = baseAxisRadius * axisStretchMultiplier
        axisStretchLabel.text = String(format: "坐标轴范围 ±%.1f (%.1fx)", stretchedAxisLen, mult)

        if !plot2DView.isHidden {
            plot2DView.applyAxisStretch(multiplier: Double(mult))
            return
        }

        // 实时重建并拉伸全区域三维坐标轴与网格
        axesContainerNode?.removeFromParentNode()
        let newAxes = Surface3DBuilder.buildAxesAndGridNode(length: stretchedAxisLen, showGrid: showReferenceGrid)
        geometryContainerNode.addChildNode(newAxes)
        axesContainerNode = newAxes
    }

    @objc private func contourSliderChanged(_ sender: UISlider) {
        let val = Double(sender.value)
        if abs(val) < 0.05 || abs(val - 1.0) < 0.05 || abs(val + 1.0) < 0.05 {
            TactileFeedbackManager.shared.playAxisSnapDetent()
        }

        let fSafe = MultivariateMathParser.compileSafe3D(params.expression)

        if !analysis.isImplicitEquation && params.pageType == .singleIntegral {
            let r = abs(fSafe(val, 0, 0))
            let area = Double.pi * r * r
            contourLabel.text = String(format: "圆盘微元 x₀=%.2f | πy²=%.2f", val, area)
            revolutionDiskNode?.removeFromParentNode()
            let disk = Surface3DBuilder.buildRevolutionDifferentialDiskNode(fSafe: fSafe, sliceX: val)
            geometryContainerNode.addChildNode(disk)
            revolutionDiskNode = disk
            return
        }

        contourLabel.text = String(format: "截面与等值线 z = %.2f", val)
        contourSliceNode?.removeFromParentNode()

        let boundSpan = Double(baseAxisRadius * axisStretchMultiplier * 0.85)
        let slice = Surface3DBuilder.buildContourSliceAndProjectionNode(
            fSafe: fSafe,
            xMin: analysis.isImplicitEquation ? -boundSpan : params.xMin,
            xMax: analysis.isImplicitEquation ? boundSpan : params.xMax,
            yMin: analysis.isImplicitEquation ? -boundSpan : params.yMin,
            yMax: analysis.isImplicitEquation ? boundSpan : params.yMax,
            sliceZ: val
        )
        geometryContainerNode.addChildNode(slice)
        contourSliceNode = slice
    }

    @objc private func doneTapped() {
        TactileFeedbackManager.shared.playModifierTap()
        dismiss(animated: true, completion: nil)
    }

    @objc private func modeChanged() {
        TactileFeedbackManager.shared.playModifierTap()
        refreshVisualization(resetCameraState: false)
    }

    @objc private func togglePanModeTapped() {
        TactileFeedbackManager.shared.playModifierTap()
        isPanModeEnabled.toggle()
        updatePanModeUI()
    }

    @objc private func toggleTransparencyTapped() {
        TactileFeedbackManager.shared.playModifierTap()
        let nextRaw = (transparencyMode.rawValue + 1) % 3
        transparencyMode = SurfaceTransparencyMode(rawValue: nextRaw) ?? .semiTransparent
        transparencyButton.setTitle(transparencyMode.buttonTitle, for: .normal)
        render3DGeometry(segIndex: modeSegmentedControl.selectedSegmentIndex)
    }

    @objc private func resetCameraTapped() {
        TactileFeedbackManager.shared.playKeyTap()
        axisStretchMultiplier = 1.0
        axisStretchSlider.value = 1.0
        let stretchedAxisLen = baseAxisRadius * axisStretchMultiplier
        axisStretchLabel.text = String(format: "坐标轴范围 ±%.1f (1.0x)", stretchedAxisLen)

        if !plot2DView.isHidden {
            plot2DView.applyAxisStretch(multiplier: 1.0)
            return
        }

        cameraTarget = SCNVector3(0, 0, 0)
        cameraAzimuth = Float.pi / 4.0
        cameraElevation = 0.58
        cameraDistance = max(minSafeCameraDistance * 1.65, baseAxisRadius * 1.95)
        applyCameraTransform(animated: true)

        axesContainerNode?.removeFromParentNode()
        let newAxes = Surface3DBuilder.buildAxesAndGridNode(length: stretchedAxisLen, showGrid: showReferenceGrid)
        geometryContainerNode.addChildNode(newAxes)
        axesContainerNode = newAxes
    }

    @objc private func toggleSpinTapped() {
        TactileFeedbackManager.shared.playModifierTap()
        isAutoSpinning.toggle()
        if isAutoSpinning {
            spinButton.backgroundColor = UIColor(red: 1.0, green: 0.584, blue: 0.0, alpha: 1.0)
            spinButton.setTitleColor(.black, for: .normal)
            let spin = SCNAction.repeatForever(SCNAction.rotateBy(x: 0, y: CGFloat(Double.pi * 2), z: 0, duration: 14.0))
            geometryContainerNode.runAction(spin, forKey: "autoSpin")
        } else {
            spinButton.backgroundColor = UIColor(red: 0.14, green: 0.14, blue: 0.16, alpha: 0.94)
            spinButton.setTitleColor(UIColor(red: 1.0, green: 0.584, blue: 0.0, alpha: 1.0), for: .normal)
            geometryContainerNode.removeAction(forKey: "autoSpin")
        }
    }

    @objc private func toggleGridTapped() {
        TactileFeedbackManager.shared.playModifierTap()
        showReferenceGrid.toggle()
        render3DGeometry(segIndex: modeSegmentedControl.selectedSegmentIndex)
    }

    private func refreshVisualization(resetCameraState: Bool) {
        let segIdx = modeSegmentedControl.selectedSegmentIndex

        objectSurfaceRadius = Surface3DBuilder.computeObjectSurfaceRadius(params: params, isImplicitEquation: analysis.isImplicitEquation)
        baseAxisRadius = Surface3DBuilder.computeSceneBoundingRadius(params: params, isImplicitEquation: analysis.isImplicitEquation)
        let stretchedAxisLen = baseAxisRadius * axisStretchMultiplier
        axisStretchLabel.text = String(format: "坐标轴范围 ±%.1f (%.1fx)", stretchedAxisLen, axisStretchMultiplier)

        if !analysis.isImplicitEquation && params.pageType == .singleIntegral && segIdx == 0 {
            sceneView.isHidden = true
            interactionModeBannerButton.isHidden = true
            panModeButton.isHidden = true
            transparencyButton.isHidden = true
            spinButton.isHidden = true
            gridButton.isHidden = true
            contourLabel.isHidden = true
            contourSlider.isHidden = true
            contourBar.isHidden = false

            plot2DView.isHidden = false
            plot2DView.expression = params.expression
            plot2DView.coordMode = params.coordMode
            plot2DView.integralXMin = params.xMin
            plot2DView.integralXMax = params.xMax
            let mid = 0.5 * (params.xMin + params.xMax)
            let span = max(3.5, abs(params.xMax - params.xMin) * 1.5) * Double(axisStretchMultiplier)
            plot2DView.viewXMin = mid - span
            plot2DView.viewXMax = mid + span
            plot2DView.viewYMin = -span
            plot2DView.viewYMax = span
            plot2DView.x0 = params.x0
            plot2DView.setNeedsDisplay()
            return
        }

        plot2DView.isHidden = true
        sceneView.isHidden = false
        interactionModeBannerButton.isHidden = false
        panModeButton.isHidden = false
        transparencyButton.isHidden = false
        spinButton.isHidden = false
        gridButton.isHidden = false
        contourLabel.isHidden = false
        contourSlider.isHidden = false
        contourBar.isHidden = false

        if resetCameraState {
            cameraTarget = SCNVector3(0, 0, 0)
            cameraAzimuth = Float.pi / 4.0
            cameraElevation = 0.58
            cameraDistance = max(minSafeCameraDistance * 1.65, baseAxisRadius * 1.95)
        }
        applyCameraTransform(animated: false)

        if !analysis.isImplicitEquation && params.pageType == .singleIntegral {
            let a = Float(min(params.xMin, params.xMax))
            let b = Float(max(params.xMin, params.xMax))
            contourSlider.minimumValue = a
            contourSlider.maximumValue = max(a + 0.1, b)
            contourSlider.value = 0.5 * (a + b)
        } else {
            let maxZSlide = max(2.5, objectSurfaceRadius * 0.95)
            contourSlider.minimumValue = -maxZSlide
            contourSlider.maximumValue = maxZSlide
            contourSlider.value = 0.0
        }

        render3DGeometry(segIndex: segIdx)
    }

    private func render3DGeometry(segIndex: Int) {
        geometryContainerNode.childNodes.forEach { $0.removeFromParentNode() }
        axesContainerNode = nil
        contourSliceNode = nil
        revolutionDiskNode = nil

        let fRaw = MultivariateMathParser.compileRaw3D(params.expression)
        let fSafe = MultivariateMathParser.compileSafe3D(params.expression)
        let currentOpacity = transparencyMode.opacity

        let stretchedAxisLen = baseAxisRadius * axisStretchMultiplier
        let axesNode = Surface3DBuilder.buildAxesAndGridNode(length: stretchedAxisLen, showGrid: showReferenceGrid)
        geometryContainerNode.addChildNode(axesNode)
        axesContainerNode = axesNode

        if analysis.isImplicitEquation {
            let implicitNode = Surface3DBuilder.buildImplicitEquationSurfaceNode(
                expression: params.expression,
                surfaceOpacity: currentOpacity
            )
            geometryContainerNode.addChildNode(implicitNode)
            if segIndex == 1 {
                let tangent = Surface3DBuilder.buildTangentPlaneNode(
                    x0: params.x0, y0: params.y0, z0: analysis.z0, fx: analysis.fx, fy: analysis.fy,
                    span: Double(objectSurfaceRadius * 0.45)
                )
                geometryContainerNode.addChildNode(tangent)
            }
            return
        }

        switch params.pageType {
        case .singleIntegral:
            let revNode = Surface3DBuilder.buildSolidOfRevolutionNode(
                fSafe,
                xMin: params.xMin,
                xMax: params.xMax,
                surfaceOpacity: currentOpacity
            )
            geometryContainerNode.addChildNode(revNode)

            let midX = Double(contourSlider.value)
            let r = abs(fSafe(midX, 0, 0))
            contourLabel.text = String(format: "圆盘微元 x₀=%.2f | πy²=%.2f", midX, Double.pi * r * r)
            let disk = Surface3DBuilder.buildRevolutionDifferentialDiskNode(fSafe: fSafe, sliceX: midX)
            geometryContainerNode.addChildNode(disk)
            revolutionDiskNode = disk

        case .doubleIntegral:
            let surface = Surface3DBuilder.buildSurfaceNode(
                fRaw: fRaw, fSafe: fSafe,
                xMin: params.xMin, xMax: params.xMax,
                yMin: params.yMin, yMax: params.yMax,
                coordMode: params.coordMode,
                surfaceOpacity: currentOpacity
            )
            geometryContainerNode.addChildNode(surface)

            if segIndex == 0 {
                let prisms = Surface3DBuilder.buildRiemannPrismsNode(
                    fSafe, xMin: params.xMin, xMax: params.xMax, yMin: params.yMin, yMax: params.yMax,
                    surfaceOpacity: max(0.22, currentOpacity * 0.8)
                )
                geometryContainerNode.addChildNode(prisms)
            } else if segIndex == 1 {
                let tangent = Surface3DBuilder.buildTangentPlaneNode(
                    x0: params.x0, y0: params.y0, z0: analysis.z0, fx: analysis.fx, fy: analysis.fy
                )
                geometryContainerNode.addChildNode(tangent)
            } else if segIndex == 2 {
                let slice = Surface3DBuilder.buildContourSliceAndProjectionNode(
                    fSafe: fSafe,
                    xMin: params.xMin, xMax: params.xMax,
                    yMin: params.yMin, yMax: params.yMax,
                    sliceZ: Double(contourSlider.value)
                )
                geometryContainerNode.addChildNode(slice)
                contourSliceNode = slice
            }

        case .tripleIntegral:
            if segIndex == 0 {
                let voxelCloud = Surface3DBuilder.buildTripleIntegralVoxelCloudNode(
                    fSafe,
                    xMin: params.xMin, xMax: params.xMax,
                    yMin: params.yMin, yMax: params.yMax,
                    zMin: params.zMin, zMax: params.zMax,
                    surfaceOpacity: currentOpacity
                )
                geometryContainerNode.addChildNode(voxelCloud)
            } else {
                let slices = Surface3DBuilder.buildTripleIntegralOrthogonalSlicesNode(
                    fSafe,
                    xMin: params.xMin, xMax: params.xMax,
                    yMin: params.yMin, yMax: params.yMax,
                    zMin: params.zMin, zMax: params.zMax,
                    surfaceOpacity: currentOpacity
                )
                geometryContainerNode.addChildNode(slices)
            }
        }
    }
}