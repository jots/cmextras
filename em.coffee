do ->
  Pos = CodeMirror.Pos

  # Boundaries of various units

  byChar = (cm, pos, dir) ->
    cm.findPosH pos, dir, 'char', true

  byWord = (cm, pos, dir) ->
    cm.findPosH pos, dir, 'word', true

  byLine = (cm, pos, dir) ->
    cm.findPosV pos, dir, 'line', cm.doc.sel.goalColumn

  byPage = (cm, pos, dir) ->
    cm.findPosV pos, dir, 'page', cm.doc.sel.goalColumn

  byParagraph = (cm, pos, dir) ->
    num = pos.line
    line = cm.getLine(num)
    sawText = /\S/.test(if dir < 0 then line.slice(0, pos.ch) else line.slice(pos.ch))
    fst = cm.firstLine()
    lst = cm.lastLine()
    loop
      num += dir
      if num < fst or num > lst
        return cm.clipPos(Pos(num - dir, if dir < 0 then 0 else null))
      line = cm.getLine(num)
      hasText = /\S/.test(line)
      if hasText
        sawText = true
      else if sawText
        return Pos(num, 0)
    return

  bySentence = (cm, pos, dir) ->
    line = pos.line
    ch = pos.ch
    text = cm.getLine(pos.line)
    sawWord = false
    loop
      next = text.charAt(ch + (if dir < 0 then -1 else 0))
      if !next
        # End/beginning of line reached
        if line == (if dir < 0 then cm.firstLine() else cm.lastLine())
          return Pos(line, ch)
        text = cm.getLine(line + dir)
        if !/\S/.test(text)
          return Pos(line, ch)
        line += dir
        ch = if dir < 0 then text.length else 0
        continue
      if sawWord and /[!?.]/.test(next)
        return Pos(line, ch + (if dir > 0 then 1 else 0))
      if !sawWord
        sawWord = /\w/.test(next)
      ch += dir
    return

  byExpr = (cm, pos, dir) ->
    wrap = undefined
    if cm.findMatchingBracket and (wrap = cm.findMatchingBracket(pos, true)) and wrap.match and (if wrap.forward then 1 else -1) == dir
      return if dir > 0 then Pos(wrap.to.line, wrap.to.ch + 1) else wrap.to
    first = true
    loop
      token = cm.getTokenAt(pos)
      after = Pos(pos.line, if dir < 0 then token.start else token.end)
      if first and dir > 0 and token.end == pos.ch or !/\w/.test(token.string)
        newPos = cm.findPosH(after, dir, 'char')
        if posEq(after, newPos)
          return pos
        else
          pos = newPos
      else
        return after
      first = false
    return


  repeated = (cmd) ->
    f = if typeof cmd == 'string' then ((cm) ->
      cm.execCommand cmd
      return
    ) else cmd
    (cm) ->
      prefix = getPrefix(cm)
      f cm
      i = 1
      while i < prefix
        f cm
        ++i
      return

  findEnd = (cm, pos, byy, dir) ->
    prefix = getPrefix(cm)
    if prefix < 0
      dir = -dir
      prefix = -prefix
    i = 0
    while i < prefix
      newPos = byy(cm, pos, dir)
      if posEq(newPos, pos)
        break
      pos = newPos
      ++i
    pos

  move = (byy, dir) ->

    f = (cm) ->
      cm.extendSelection findEnd(cm, cm.getCursor(), byy, dir)
      return

    f.motion = true
    f


  # Kill 'ring'
  killRing = []
  lastKill = null
  prefixPreservingKeys = 
    'Alt-G': true
    'Ctrl-X': true
    'Ctrl-Q': true
    'Ctrl-U': true


  prefixMap = 'Ctrl-G': clearPrefix

  posEq = (a, b) ->
    a.line == b.line and a.ch == b.ch

  addToRing = (str) ->
    killRing.push str
    if killRing.length > 50
      killRing.shift()
    return

  growRingTop = (str) ->
    if !killRing.length
      return addToRing(str)
    killRing[killRing.length - 1] += str
    return

  getFromRing = (n) ->
    killRing[killRing.length - (if n then Math.min(n, 1) else 1)] or ''

  popFromRing = ->
    if killRing.length > 1
      killRing.pop()
    getFromRing()

  kill = (cm, from, to, mayGrow, text) ->
    if text == null
      text = cm.getRange(from, to)
    if mayGrow and lastKill and lastKill.cm == cm and posEq(from, lastKill.pos) and cm.isClean(lastKill.gen)
      growRingTop text
    else
      addToRing text
    cm.replaceRange '', from, to, '+delete'
    if mayGrow
      lastKill =
        cm: cm
        pos: from
        gen: cm.changeGeneration()
    else
      lastKill = null
    return


  # Prefixes (only crudely supported)

  getPrefix = (cm, precise) ->
    digits = cm.state.emacsPrefix
    if !digits
      return if precise then null else 1
    clearPrefix cm
    if digits == '-' then -1 else Number(digits)


  killTo = (cm, byy, dir) ->
    selections = cm.listSelections()
    cursor = undefined
    i = selections.length
    while i--
      cursor = selections[i].head
      kill cm, cursor, findEnd(cm, cursor, byy, dir), true
    return

  killRegion = (cm) ->
    if cm.somethingSelected()
      selections = cm.listSelections()
      selection = undefined
      i = selections.length
      while i--
        selection = selections[i]
        kill cm, selection.anchor, selection.head
      return true
    return

  addPrefix = (cm, digit) ->
    if cm.state.emacsPrefix
      if digit != '-'
        cm.state.emacsPrefix += digit
      return
    # Not active yet
    cm.state.emacsPrefix = digit
    cm.on 'keyHandled', maybeClearPrefix
    cm.on 'inputRead', maybeDuplicateInput
    return

  maybeClearPrefix = (cm, arg) ->
    if !cm.state.emacsPrefixMap and !prefixPreservingKeys.hasOwnProperty(arg)
      clearPrefix cm
    return

  clearPrefix = (cm) ->
    cm.state.emacsPrefix = null
    cm.off 'keyHandled', maybeClearPrefix
    cm.off 'inputRead', maybeDuplicateInput
    return

  maybeDuplicateInput = (cm, event) ->
    dup = getPrefix(cm)
    if dup > 1 and event.origin == '+input'
      one = event.text.join('\n')
      txt = ''
      i = 1
      while i < dup
        txt += one
        ++i
      cm.replaceSelection txt
    return

  addPrefixMap = (cm) ->
    cm.state.emacsPrefixMap = true
    cm.addKeyMap prefixMap
    cm.on 'keyHandled', maybeRemovePrefixMap
    cm.on 'inputRead', maybeRemovePrefixMap
    return

  maybeRemovePrefixMap = (cm, arg) ->
    if typeof arg == 'string' and (/^\d$/.test(arg) or arg == 'Ctrl-U')
      return
    cm.removeKeyMap prefixMap
    cm.state.emacsPrefixMap = false
    cm.off 'keyHandled', maybeRemovePrefixMap
    cm.off 'inputRead', maybeRemovePrefixMap
    return

  # Utilities

  setMark = (cm) ->
    console.log "setmark" 
    cm.setCursor cm.getCursor()
    cm.setExtending !cm.getExtending()
    cm.on 'change', ->
      cm.setExtending false
      return
    return

  clearMark = (cm) ->
    cm.setExtending false
    cm.setCursor cm.getCursor()
    return

  getInput = (cm, msg, f) ->
    if cm.openDialog
      cm.openDialog msg + ': <input type="text" style="width: 10em"/>', f, bottom: true
    else
      f prompt(msg, '')
    return

  operateOnWord = (cm, op) ->
    start = cm.getCursor()
    end = cm.findPosH(start, 1, 'word')
    cm.replaceRange op(cm.getRange(start, end)), start, end
    cm.setCursor end
    return

  toEnclosingExpr = (cm) ->
    `var ch`
    pos = cm.getCursor()
    line = pos.line
    ch = pos.ch
    stack = []
    while line >= cm.firstLine()
      text = cm.getLine(line)
      i = if ch == null then text.length else ch
      while i > 0
        ch = text.charAt(--i)
        if ch == ')'
          stack.push '('
        else if ch == ']'
          stack.push '['
        else if ch == '}'
          stack.push '{'
        else if /[\(\{\[]/.test(ch) and (!stack.length or stack.pop() != ch)
          return cm.extendSelection(Pos(line, i))
      --line
      ch = null
    return

  quit = (cm) ->
    cm.execCommand 'clearSearch'
    clearMark cm
    return



  # Actual keymap
  keyMap = CodeMirror.keyMap.emacs = CodeMirror.normalizeKeyMap(
    'Ctrl-W': (cm) ->
      kill cm, cm.getCursor('start'), cm.getCursor('end')
      return
    'Ctrl-K': repeated((cm) ->
      start = cm.getCursor()
      end = cm.clipPos(Pos(start.line))
      text = cm.getRange(start, end)
      if !/\S/.test(text)
        text += '\n'
        end = Pos(start.line + 1, 0)
      kill cm, start, end, true, text
      return
    )
    'Alt-W': (cm) ->
      addToRing cm.getSelection()
      clearMark cm
      return
    'Ctrl-Y': (cm) ->
      start = cm.getCursor()
      cm.replaceRange getFromRing(getPrefix(cm)), start, start, 'paste'
      cm.setSelection start, cm.getCursor()
      return
    'Alt-Y': (cm) ->
      cm.replaceSelection popFromRing(), 'around', 'paste'
      return
    'Ctrl-Space': setMark
    'Ctrl-Shift-2': setMark
    'Ctrl-F': move(byChar, 1)
    'Ctrl-B': move(byChar, -1)
    'Right': move(byChar, 1)
    'Left': move(byChar, -1)
    'Ctrl-D': (cm) ->
      killTo cm, byChar, 1
      return
    'Delete': (cm) ->
      killRegion(cm) or killTo(cm, byChar, 1)
      return
    'Ctrl-H': (cm) ->
      killTo cm, byChar, -1
      return
    'Backspace': (cm) ->
      killRegion(cm) or killTo(cm, byChar, -1)
      return
    'Alt-F': move(byWord, 1)
    'Alt-B': move(byWord, -1)
    'Alt-D': (cm) ->
      killTo cm, byWord, 1
      return
    'Alt-Backspace': (cm) ->
      killTo cm, byWord, -1
      return
    'Ctrl-N': move(byLine, 1)
    'Ctrl-P': move(byLine, -1)
    'Down': move(byLine, 1)
    'Up': move(byLine, -1)
    'Ctrl-A': 'goLineStart'
    'Ctrl-E': 'goLineEnd'
    'End': 'goDocEnd' #'goLineEnd'
    'Home': 'goDocStart' #'goLineStart'
    'Alt-V': move(byPage, -1)
    'Ctrl-V': move(byPage, 1)
    'PageUp': move(byPage, -1)
    'PageDown': move(byPage, 1)
    'Ctrl-Up': move(byParagraph, -1)
    'Ctrl-Down': move(byParagraph, 1)
    'Alt-A': move(bySentence, -1)
    'Alt-E': move(bySentence, 1)
    'Alt-K': (cm) ->
      killTo cm, bySentence, 1
      return
    'Ctrl-Alt-K': (cm) ->
      killTo cm, byExpr, 1
      return
    'Ctrl-Alt-Backspace': (cm) ->
      killTo cm, byExpr, -1
      return
    'Ctrl-Alt-F': move(byExpr, 1)
    'Ctrl-Alt-B': move(byExpr, -1)
    'Shift-Ctrl-Alt-2': (cm) ->
      cursor = cm.getCursor()
      cm.setSelection findEnd(cm, cursor, byExpr, 1), cursor
      return
    'Ctrl-Alt-T': (cm) ->
      leftStart = byExpr(cm, cm.getCursor(), -1)
      leftEnd = byExpr(cm, leftStart, 1)
      rightEnd = byExpr(cm, leftEnd, 1)
      rightStart = byExpr(cm, rightEnd, -1)
      cm.replaceRange cm.getRange(rightStart, rightEnd) + cm.getRange(leftEnd, rightStart) + cm.getRange(leftStart, leftEnd), leftStart, rightEnd
      return
    'Ctrl-Alt-U': repeated(toEnclosingExpr)
    'Alt-Space': (cm) ->
      pos = cm.getCursor()
      from = pos.ch
      to = pos.ch
      text = cm.getLine(pos.line)
      while from and /\s/.test(text.charAt(from - 1))
        --from
      while to < text.length and /\s/.test(text.charAt(to))
        ++to
      cm.replaceRange ' ', Pos(pos.line, from), Pos(pos.line, to)
      return
    'Ctrl-O': repeated((cm) ->
      cm.replaceSelection '\n', 'start'
      return
    )
    'Ctrl-T': repeated((cm) ->
      cm.execCommand 'transposeChars'
      return
    )
    'Alt-C': repeated((cm) ->
      operateOnWord cm, (w) ->
        letter = w.search(/\w/)
        if letter == -1
          return w
        w.slice(0, letter) + w.charAt(letter).toUpperCase() + w.slice(letter + 1).toLowerCase()
      return
    )
    'Alt-U': repeated((cm) ->
      operateOnWord cm, (w) ->
        w.toUpperCase()
      return
    )
    'Alt-L': repeated((cm) ->
      operateOnWord cm, (w) ->
        w.toLowerCase()
      return
    )
    'Alt-;': 'toggleComment'
    'Ctrl-/': repeated('undo')
    'Shift-Ctrl--': repeated('undo')
    'Ctrl-Z': repeated('undo')
    'Cmd-Z': repeated('undo')
    'Shift-Alt-,': 'goDocStart'
    'Shift-Alt-.': 'goDocEnd'
    'Ctrl-S': 'findNext'
    'Ctrl-R': 'findPrev'
    'Ctrl-G': quit
    'Shift-Alt-5': 'replace'
    'Alt-/': 'autocomplete'
    'Ctrl-J': 'newlineAndIndent'
    'Enter': false
    'Tab': (cm) ->
      if cm.somethingSelected()
        cm.indentSelection 'add'
      else
        cm.indentSelection 'smart'
      return
    'Alt-G G': (cm) ->
      prefix = getPrefix(cm, true)
      if prefix != null and prefix > 0
        return cm.setCursor(prefix - 1)
      getInput cm, 'Goto line', (str) ->
        num = undefined
        if str and !isNaN(num = Number(str)) and num == (num | 0) and num > 0
          cm.setCursor num - 1
        return
      return
    'Ctrl-X Tab': (cm) ->
      cm.indentSelection getPrefix(cm, true) or cm.getOption('indentUnit')
      return
    'Ctrl-X Ctrl-X': (cm) ->
      cm.setSelection cm.getCursor('head'), cm.getCursor('anchor')
      return
    'Ctrl-X Ctrl-S': 'save'
    'Ctrl-X Ctrl-W': 'save'
    'Ctrl-X S': 'saveAll'
    'Ctrl-X F': 'open'
    'Ctrl-X U': repeated('undo')
    'Ctrl-X K': 'close'
    'Ctrl-X Delete': (cm) ->
      kill cm, cm.getCursor(), bySentence(cm, cm.getCursor(), 1), true
      return
    'Ctrl-X H': 'selectAll'
    'Ctrl-Q Tab': repeated('insertTab')
    'Ctrl-U': addPrefixMap)

  regPrefix = (d) ->

    prefixMap[d] = (cm) ->
      addPrefix cm, d
      return

    keyMap['Ctrl-' + d] = (cm) ->
      addPrefix cm, d
      return

    prefixPreservingKeys['Ctrl-' + d] = true
    return

  i = 0
  while i < 10
    regPrefix String(i)
    ++i
  regPrefix '-'

