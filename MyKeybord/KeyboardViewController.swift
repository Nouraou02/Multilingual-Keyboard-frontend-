//
//  KeyboardViewController.swift
//  MyKeybord
//

import UIKit

class KeyboardViewController: UIInputViewController {
    
    // --- UI COMPONENTS ---
    @IBOutlet var nextKeyboardButton: UIButton!
    var popupView: UIStackView?
    let mainStack = UIStackView()
    let candidateStack = UIStackView()
    let suggestionBar = UIStackView()
    var candidateLabels: [UILabel] = []
    
    // --- IME STATE ---
    var isUppercase = false
    var keyboardMode: KeyboardMode = .letters
    var alternatives: [String] = [], currentSelectedIndex = -1, longPressActive = false
    var isChineseLineEnabled: Bool = true
    var pinyinBuffer: String = ""
    var pinyinDictionary: [String: [String]] = [:]
    var predictionTimer: Timer?
    enum KeyboardMode { case letters, numbers, symbols }

    let keyAlternatives: [String: [String]] = [
        "e": ["é", "è", "ê", "ë"], "a": ["à", "â"], "i": ["î", "ï"], "o": ["ô"], "u": ["ù", "û"], "c": ["ç"]
    ]
    
    let letterRows = [["q","w","e","r","t","y","u","i","o","p"], ["a","s","d","f","g","h","j","k","l"], ["⇧","z","x","c","v","b","n","m","⌫"]]
    let numberRows = [["1","2","3","4","5","6","7","8","9","0"], ["-","/",":",";","(",")","$","&","@","\""], ["#+=",".",",","?","!","'","⌫"]]
    let symbolRows = [["[","]","{","}","#","%","^","*","+","="], ["_","\\","|","~","<",">","€","£","¥","•"], ["123",".",",","?","!","'","⌫"]]

    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupNextKeyboardButton()
        loadPinyinDictionary()
        setupUI()
        setupKeyboard()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard let _ = self.inputView else { return }
        updateNextKeyboardButtonVisibility()
        updatePredictions()
    }
    
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        updateNextKeyboardButtonVisibility()
    }
    
    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        
        let proxy = self.textDocumentProxy
        let textColor = (proxy.keyboardAppearance == .dark) ? UIColor.white : UIColor.black
        self.nextKeyboardButton?.setTitleColor(textColor, for: [])
        
        updateChineseCandidateLine()
        updatePredictions()
    }

    // MARK: - Setup Next Keyboard Button
    
    private func setupNextKeyboardButton() {
        self.nextKeyboardButton = UIButton(type: .system)
        self.nextKeyboardButton.setTitle(NSLocalizedString("Next Keyboard", comment: "Title for 'Next Keyboard' button"), for: [])
        self.nextKeyboardButton.sizeToFit()
        self.nextKeyboardButton.translatesAutoresizingMaskIntoConstraints = false
        self.nextKeyboardButton.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        self.view.addSubview(self.nextKeyboardButton)
        
        self.nextKeyboardButton.leftAnchor.constraint(equalTo: self.view.leftAnchor).isActive = true
        self.nextKeyboardButton.bottomAnchor.constraint(equalTo: self.view.bottomAnchor).isActive = true
    }
    
    private func updateNextKeyboardButtonVisibility() {
        guard self.nextKeyboardButton != nil else { return }
        self.nextKeyboardButton.isHidden = !self.needsInputModeSwitchKey
    }

    // MARK: - Dictionary Loading
    
    private func loadPinyinDictionary() {
        let keyboardBundle = Bundle(for: Self.self)
        if let path = keyboardBundle.path(forResource: "pinyin_dict", ofType: "json") {
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: path))
                if let decoded = try JSONSerialization.jsonObject(with: data, options: []) as? [String: [String]] {
                    self.pinyinDictionary = decoded
                }
            } catch {
                print("IME JSON ERROR: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Main UI Setup
    
    private func setupUI() {
        view.backgroundColor = .clear
        
        suggestionBar.axis = .horizontal
        suggestionBar.spacing = 8
        suggestionBar.distribution = .fillEqually
        suggestionBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(suggestionBar)
        
        for i in 0..<3 {
            let l = UILabel(); l.tag = 101 + i; l.textAlignment = .center; l.font = .systemFont(ofSize: 17, weight: .medium)
            l.backgroundColor = UIColor.white.withAlphaComponent(0.25); l.layer.cornerRadius = 6; l.clipsToBounds = true; l.isUserInteractionEnabled = true
            l.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(predictionTapped(_:))))
            suggestionBar.addArrangedSubview(l)
        }
        
        candidateStack.axis = .horizontal; candidateStack.spacing = 6; candidateStack.distribution = .fillEqually; candidateStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(candidateStack)
        
        for i in 0..<5 {
            let l = UILabel(); l.tag = 201 + i; l.textAlignment = .center; l.font = .systemFont(ofSize: 19, weight: .bold)
            l.textColor = .black
            l.backgroundColor = UIColor.systemGray.withAlphaComponent(0.15)
            l.layer.cornerRadius = 6; l.clipsToBounds = true; l.isUserInteractionEnabled = true
            l.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(chineseCandidateTapped(_:))))
            
            candidateStack.addArrangedSubview(l)
            candidateLabels.append(l)
            l.text = ""
        }

        mainStack.axis = .vertical; mainStack.spacing = 8; mainStack.distribution = .fillEqually; mainStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(mainStack)

        NSLayoutConstraint.activate([
            suggestionBar.topAnchor.constraint(equalTo: view.topAnchor, constant: 5),
            suggestionBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 5),
            suggestionBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -5),
            suggestionBar.heightAnchor.constraint(equalToConstant: 38),
            
            candidateStack.topAnchor.constraint(equalTo: suggestionBar.bottomAnchor, constant: 4),
            candidateStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 5),
            candidateStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -5),
            candidateStack.heightAnchor.constraint(equalToConstant: 38),
            
            mainStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 5),
            mainStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -5),
            mainStack.topAnchor.constraint(equalTo: candidateStack.bottomAnchor, constant: 6),
            mainStack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -5),
            
            view.heightAnchor.constraint(equalToConstant: 320)
        ])
        
        candidateStack.isHidden = false
    }

    // MARK: - Read Language from Spacebar
    
    func getActiveLanguage() -> String {
        guard let spaceButton = self.view.viewWithTag(999) as? UIButton,
              let spaceLabel = spaceButton.viewWithTag(99) as? UILabel,
              let currentLang = spaceLabel.text else {
            return "en_US"
        }
        
        // Map the server's output on the spacebar to Apple's internal dictionary codes
        switch currentLang.uppercased() {
        case "FR": return "fr_FR"
        case "ZH": return "zh_CN"
        default: return "en_US"
        }
    }

    // MARK: - Native Dictionary Helper
    
    func getNativeCompletions(for partialWord: String, languageCode: String) -> [String] {
        let textChecker = UITextChecker()
        let nsString = partialWord as NSString
        let range = NSRange(location: 0, length: nsString.length)
        
        let completions = textChecker.completions(forPartialWordRange: range,
                                                  in: partialWord,
                                                  language: languageCode) ?? []
        
        let finalCompletions = Array(completions.prefix(3))
        
        // 🚨 YOUR DIAGNOSTIC LOG IS HERE 🚨
        print("🔍 MID-WORD LOG | Typed: '\(partialWord)' | Lang: \(languageCode) | Suggestions: \(finalCompletions)")
        
        return finalCompletions
    }

    // MARK: - Local Pinyin Lookup Mechanics
    
    func updateChineseCandidateLine() {
        let lookupKey = pinyinBuffer.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        var rawMatches: [String] = []
        
        if lookupKey.isEmpty {
            renderCandidates(matches: [])
            return
        }
        
        if let directPhraseMatches = pinyinDictionary[lookupKey] {
            rawMatches.append(contentsOf: directPhraseMatches)
        }
        
        var currentStr = lookupKey
        var segments: [String] = []
        
        while !currentStr.isEmpty {
            var foundSegment = false
            for len in stride(from: min(currentStr.count, 6), through: 1, by: -1) {
                let index = currentStr.index(currentStr.startIndex, offsetBy: len)
                let prefix = String(currentStr[..<index])
                
                if pinyinDictionary[prefix] != nil {
                    segments.append(prefix)
                    currentStr = String(currentStr[index...])
                    foundSegment = true
                    break
                }
            }
            if !foundSegment {
                currentStr.removeFirst()
            }
        }
        
        var fullSentenceVariants: [String] = [""]
        let maxPhraseLength = 5
        let limitedSegments = Array(segments.prefix(maxPhraseLength))
        
        for seg in limitedSegments {
            if let charactersForSyllable = pinyinDictionary[seg] {
                let topChoices = Array(charactersForSyllable.prefix(3))
                var newVariants: [String] = []
                
                for prefixString in fullSentenceVariants {
                    for character in topChoices {
                        newVariants.append(prefixString + character)
                    }
                }
                fullSentenceVariants = newVariants
            }
        }
        
        for sentence in fullSentenceVariants {
            if !sentence.isEmpty {
                rawMatches.append(sentence)
            }
        }
        
        if let firstSyllable = segments.first, let individualOptions = pinyinDictionary[firstSyllable] {
            rawMatches.append(contentsOf: individualOptions)
        }
        
        var uniqueMatches: [String] = []
        for item in rawMatches {
            if !uniqueMatches.contains(item) {
                uniqueMatches.append(item)
            }
        }
        
        renderCandidates(matches: uniqueMatches)
    }

    private func renderCandidates(matches: [String]) {
        UIView.performWithoutAnimation {
            candidateLabels.forEach { label in
                candidateStack.removeArrangedSubview(label)
                label.removeFromSuperview()
            }
            
            guard !matches.isEmpty else { return }
            let primaryMatch = matches[0]
            
            if primaryMatch.count >= 3 {
                let firstLabel = candidateLabels[0]
                firstLabel.text = primaryMatch
                firstLabel.textColor = .black
                firstLabel.backgroundColor = UIColor.white.withAlphaComponent(0.8)
                firstLabel.isHidden = false
                
                candidateStack.addArrangedSubview(firstLabel)
                
                for i in 1..<5 {
                    candidateLabels[i].text = ""
                    candidateLabels[i].isHidden = true
                }
            } else {
                let validCount = min(matches.count, 5)
                for i in 0..<5 {
                    let label = candidateLabels[i]
                    if i < validCount {
                        label.text = matches[i]
                        label.textColor = .black
                        label.backgroundColor = UIColor.white.withAlphaComponent(0.8)
                        label.isHidden = false
                        candidateStack.addArrangedSubview(label)
                    } else {
                        label.text = ""
                        label.isHidden = true
                    }
                }
            }
            self.candidateStack.layoutIfNeeded()
        }
    }
    
    // MARK: - Server-Side Prediction Dispatch
    func updatePredictions() {
        guard let context = self.textDocumentProxy.documentContextBeforeInput, !context.isEmpty else {
            self.suggestionBar.setSuggestions(["the", "and", "of"])
            return
        }
        
        let langCode = self.getActiveLanguage()
        
        // 1. PINYIN SHIELD: Only intercept if Chinese is the active language
        if langCode == "zh_CN" && !pinyinBuffer.isEmpty {
            self.suggestionBar.setSuggestions(["", "", ""])
            return
        }

        // 2. IS THE WORD FINISHED? (Next-Word via Network)
        // Check if there is a space OR if the last typed character is Chinese Hanzi
        let endsWithChinese = context.range(of: "\\p{Han}$", options: .regularExpression) != nil
        
        if context.hasSuffix(" ") || endsWithChinese {
            self.suggestionBar.setSuggestions(["...", "...", "..."])
            
            NetworkManager.shared.fetchPredictions(for: context) { [weak self] predictions, adapterLabel in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    
                    if let safePredictions = predictions, let safeAdapter = adapterLabel {
                        self.updateUIWithPredictions(safePredictions, language: safeAdapter)
                        self.suggestionBar.isHidden = false
                    } else {
                        self.suggestionBar.setSuggestions(["", "", ""])
                    }
                }
            }
        } else {
            // 3. MID-WORD TYPING (Local iOS Dictionary with Fallback Cascade)
            let words = context.components(separatedBy: .whitespaces)
            guard let lastWord = words.last, !lastWord.isEmpty else { return }
            
            let cleanWord = lastWord.trimmingCharacters(in: .punctuationCharacters)
            if cleanWord.isEmpty { return }
            
            // Attempt 1: Check the active language
            var fastSuggestions = getNativeCompletions(for: cleanWord, languageCode: langCode)
            
            // Attempt 2: Dictionary Fallback Cascade
            if fastSuggestions.isEmpty {
                // If English fails, try French. If French/Chinese fails, try English.
                let fallbackLang = (langCode == "en_US") ? "fr_FR" : "en_US"
                fastSuggestions = getNativeCompletions(for: cleanWord, languageCode: fallbackLang)
                
                // If the fallback found words, visually update the spacebar to reflect the correction
                if !fastSuggestions.isEmpty {
                    if let spaceButton = self.view.viewWithTag(999) as? UIButton,
                       let spaceLabel = spaceButton.viewWithTag(99) as? UILabel {
                        spaceLabel.text = (fallbackLang == "en_US") ? "EN" : "FR"
                    }
                }
            }
            
            self.suggestionBar.setSuggestions(fastSuggestions)
        }
    }

    private func updateUIWithPredictions(_ predictions: [String], language: String) {
        // Dynamically update space bar text to display active routing adapter
        if let sb = self.view.viewWithTag(999) as? UIButton, let sl = sb.viewWithTag(99) as? UILabel {
            sl.text = language.uppercased()
        }
        
        // Update the 3 prediction candidate labels
        for i in 0..<3 {
            if let l = self.view.viewWithTag(101 + i) as? UILabel {
                let processedWord = (i < predictions.count) ? predictions[i] : ""
                l.text = processedWord
                l.backgroundColor = processedWord.isEmpty ? UIColor.white.withAlphaComponent(0.1) : UIColor.white.withAlphaComponent(0.5)
            }
        }
    }

    // MARK: - Candidate Selection Events
    
    @objc func chineseCandidateTapped(_ sender: UITapGestureRecognizer) {
        guard let label = sender.view as? UILabel, let selectedHanzi = label.text, !selectedHanzi.isEmpty else { return }
        
        for _ in 0..<pinyinBuffer.count {
            textDocumentProxy.deleteBackward()
        }
        
        textDocumentProxy.insertText(selectedHanzi)
        pinyinBuffer = ""
        
        updateChineseCandidateLine()
        updatePredictions()
    }

    @objc func predictionTapped(_ sender: UITapGestureRecognizer) {
        guard let label = sender.view as? UILabel, let selectedText = label.text, !selectedText.isEmpty else { return }
        
        let context = textDocumentProxy.documentContextBeforeInput ?? ""
        let isChinese = selectedText.range(of: "\\p{Han}", options: .regularExpression) != nil
        
        if isChinese {
            textDocumentProxy.insertText(selectedText)
        } else {
            let components = context.components(separatedBy: .whitespaces)
            if let lastFragment = components.last, !lastFragment.isEmpty {
                for _ in 0..<lastFragment.count { textDocumentProxy.deleteBackward() }
            }
            textDocumentProxy.insertText(selectedText + " ")
        }
        
        pinyinBuffer = ""
        updateChineseCandidateLine()
        updatePredictions()
    }

    // MARK: - Physical Keyboard Interceptor
    
    @objc func keyTapped(_ sender: UIButton) {
        if longPressActive || popupView != nil { return }
        let t = sender.accessibilityLabel ?? ""
        
        switch t {
        case "⌫":
            textDocumentProxy.deleteBackward()
            if !pinyinBuffer.isEmpty { pinyinBuffer.removeLast() }
        case "SPACE":
            textDocumentProxy.insertText(" ")
            pinyinBuffer = ""
        case "RETURN":
            textDocumentProxy.insertText("\n")
            pinyinBuffer = ""
        case "⇧":
            isUppercase.toggle(); setupKeyboard()
        case "123":
            keyboardMode = .numbers; setupKeyboard()
        case "ABC":
            keyboardMode = .letters; setupKeyboard()
        case "#+=":
            keyboardMode = .symbols; setupKeyboard()
        default:
            let char = (sender.viewWithTag(99) as? UILabel)?.text ?? ""
            textDocumentProxy.insertText(char)
            
            if keyboardMode == .letters && char.range(of: "[a-zA-Z]", options: .regularExpression) != nil {
                pinyinBuffer += char
            } else {
                pinyinBuffer = ""
            }
        }
        
        updateChineseCandidateLine()
        updatePredictions()
    }

    // MARK: - UI Auto-Layout Generation Logic
    
    func setupKeyboard() {
        mainStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let rows = (keyboardMode == .letters) ? letterRows : (keyboardMode == .numbers ? numberRows : symbolRows)
        rows.forEach { mainStack.addArrangedSubview(createRow(keys: $0)) }
        mainStack.addArrangedSubview(createBottomRow())
    }

    func createKeyButton(title: String) -> UIButton {
        let b = UIButton(type: .custom); b.layer.cornerRadius = 6; b.backgroundColor = .white.withAlphaComponent(0.4)
            b.layer.borderWidth = 0.5; b.layer.borderColor = UIColor.black.withAlphaComponent(0.1).cgColor
        let l = UILabel(); l.tag = 99; l.textAlignment = .center; l.font = .systemFont(ofSize: 22); l.textColor = .black
        l.translatesAutoresizingMaskIntoConstraints = false; b.addSubview(l)
        NSLayoutConstraint.activate([l.centerXAnchor.constraint(equalTo: b.centerXAnchor), l.centerYAnchor.constraint(equalTo: b.centerYAnchor)])
        b.accessibilityLabel = title; updateBtn(b, title)
        b.addTarget(self, action: #selector(keyTapped(_:)), for: .touchUpInside)
        if keyboardMode == .letters && keyAlternatives[title.lowercased()] != nil {
            let lp = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:))); lp.minimumPressDuration = 0.35; b.addGestureRecognizer(lp)
        }
        return b
    }

    func updateBtn(_ b: UIButton, _ t: String) {
        guard let l = b.viewWithTag(99) as? UILabel else { return }
        if t == "⇧" { l.text = "⇧"; b.backgroundColor = isUppercase ? .black : .white.withAlphaComponent(0.4); l.textColor = isUppercase ? .white : .black }
        else if t == "RETURN" { l.text = "⏎" } else if t == "SPACE" { l.text = "EN" }
        else { l.text = (isUppercase && t.count == 1) ? t.uppercased() : t }
    }

    func createRow(keys: [String]) -> UIStackView {
        let r = UIStackView(); r.axis = .horizontal; r.spacing = 6; r.distribution = .fillEqually
        keys.forEach { r.addArrangedSubview(createKeyButton(title: $0)) }; return r
    }

    func createBottomRow() -> UIStackView {
        let r = UIStackView(); r.axis = .horizontal; r.spacing = 6; r.distribution = .fillProportionally
        let m = createKeyButton(title: (keyboardMode == .letters) ? "123" : "ABC")
        let s = createKeyButton(title: "SPACE"); s.tag = 999
        let ret = createKeyButton(title: "RETURN")
        NSLayoutConstraint.activate([m.widthAnchor.constraint(equalToConstant: 55), s.widthAnchor.constraint(equalToConstant: 170), ret.widthAnchor.constraint(equalToConstant: 75)])
        [m, s, ret].forEach { r.addArrangedSubview($0) }; return r
    }

    // MARK: - Long Press Popup Mechanics
    
    @objc func handleLongPress(_ g: UILongPressGestureRecognizer) {
        guard let b = g.view as? UIButton, let k = b.accessibilityLabel?.lowercased(), let alts = keyAlternatives[k] else { return }
        if g.state == .began { longPressActive = true; showPopup(for: b, with: alts) }
        else if g.state == .changed { updateSel(at: g.location(in: view)) }
        else if g.state == .ended {
            if currentSelectedIndex >= 0 {
                let selected = alternatives[currentSelectedIndex]
                textDocumentProxy.insertText(isUppercase ? selected.uppercased() : selected.lowercased())
                updatePredictions()
            }
            hidePopup(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.longPressActive = false }
        } else { hidePopup(); longPressActive = false }
    }

    func showPopup(for b: UIButton, with alts: [String]) {
        hidePopup(); alternatives = alts; let st = UIStackView(); st.axis = .horizontal; st.distribution = .fillEqually; st.backgroundColor = .white; st.layer.cornerRadius = 8; st.translatesAutoresizingMaskIntoConstraints = false
        alts.forEach { a in let l = UILabel(); l.text = isUppercase ? a.uppercased() : a.lowercased(); l.textAlignment = .center; st.addArrangedSubview(l) }
        view.addSubview(st); popupView = st
        NSLayoutConstraint.activate([st.bottomAnchor.constraint(equalTo: b.topAnchor, constant: -10), st.centerXAnchor.constraint(equalTo: b.centerXAnchor), st.heightAnchor.constraint(equalToConstant: 45), st.widthAnchor.constraint(equalToConstant: CGFloat(max(alts.count * 40, 60)))])
    }

    func updateSel(at loc: CGPoint) {
        guard let p = popupView else { return }
        let idx = Int(view.convert(loc, to: p).x / (p.frame.width / CGFloat(alternatives.count)))
        if idx >= 0 && idx < alternatives.count && idx != currentSelectedIndex {
            currentSelectedIndex = idx
            p.arrangedSubviews.enumerated().forEach { i, v in v.backgroundColor = (i == idx) ? .systemBlue.withAlphaComponent(0.2) : .clear }
        }
    }

    func hidePopup() { popupView?.removeFromSuperview(); popupView = nil; currentSelectedIndex = -1 }
    
}

extension UIStackView {
    func setSuggestions(_ suggestions: [String]) {
        for i in 0..<3 {
            if let label = self.viewWithTag(101 + i) as? UILabel {
                let processedWord = i < suggestions.count ? suggestions[i] : ""
                label.text = processedWord
                
                label.backgroundColor = processedWord.isEmpty ?
                    UIColor.white.withAlphaComponent(0.1) :
                    UIColor.white.withAlphaComponent(0.5)
            }
        }
    }
}
