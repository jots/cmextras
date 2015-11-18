# CodeMirror, copyright (c) by Marijn Haverbeke and others
# Distributed under an MIT license: http://codemirror.net/LICENSE

###*
# based off of:
# https://github.com/pickhardt/coffeescript-codemirror-mode
###
CodeMirror.defineMode 'coffeescript', (conf, parserConf) ->
  ERRORCLASS = 'error'
  operators = /^(?:->|=>|\+[+=]?|-[\-=]?|\*[\*=]?|\/[\/=]?|[=!]=|<[><]?=?|>>?=?|%=?|&=?|\|=?|\^=?|\~|!|\?|(or|and|\|\||&&|\?)=)/
  delimiters = /^(?:[()\[\]{},:`=;]|\.\.?\.?)/
  identifiers = /^[_A-Za-z$][_A-Za-z$0-9]*/
  atProp = /^@[_A-Za-z$][_A-Za-z$0-9]*/

  wordRegexp = (words) ->
    new RegExp('^((' + words.join(')|(') + '))\\b')
    
  wordops = "and,or,not,is,isnt,in,instanceof,typeof"
  wordOperators = wordRegexp(wordops.split(","))

  ikw = "for,while,loop,if,unless,else,switch,try,catch,finally,when,class"
  ikwlist = ikw.split(",")
  indentKeywords = wordRegexp(ikwlist)

  kw = "break,by,continue,debugger,delete,do,in,of,"
  kw += "new,return,then,this,@,throw,until,extends"

  keywords = wordRegexp(ikwlist.concat(kw.split(",")))

  stringPrefixes = /^('{3}|\"{3}|['\"])/
  regexPrefixes = /^(\/{3}|\/)/

  cconstants = "Infinity,NaN,undefined,null,true,false,on,off,yes,no"
  constants = wordRegexp(cconstants.split(","))


  # Tokenizers

  tokenBase = (stream, state) ->
    # Handle scope changes
    if stream.sol()
      if state.scope.align == null
        state.scope.align = false
      scopeOffset = state.scope.offset
      if stream.eatSpace()
        lineOffset = stream.indentation()
        if lineOffset > scopeOffset and state.scope.type == 'coffee'
          return 'indent'
        else if lineOffset < scopeOffset
          return 'dedent'
        return null
      else
        if scopeOffset > 0
          dedent stream, state
    if stream.eatSpace()
      return null
    ch = stream.peek()
    # Handle docco title comment (single line)
    if stream.match('####')
      stream.skipToEnd()
      return 'comment'
    # Handle multi line comments
    if stream.match('###')
      state.tokenize = longComment
      return state.tokenize(stream, state)
    # Single line comment
    if ch == '#'
      stream.skipToEnd()
      return 'comment'
    # Handle number literals
    if stream.match(/^-?[0-9\.]/, false)
      floatLiteral = false
      # Floats
      if stream.match(/^-?\d*\.\d+(e[\+\-]?\d+)?/i)
        floatLiteral = true
      if stream.match(/^-?\d+\.\d*/)
        floatLiteral = true
      if stream.match(/^-?\.\d+/)
        floatLiteral = true
      if floatLiteral
        # prevent from getting extra . on 1..
        if stream.peek() == '.'
          stream.backUp 1
        return 'number'
      # Integers
      intLiteral = false
      # Hex
      if stream.match(/^-?0x[0-9a-f]+/i)
        intLiteral = true
      # Decimal
      if stream.match(/^-?[1-9]\d*(e[\+\-]?\d+)?/)
        intLiteral = true
      # Zero by itself with no other piece of number.
      if stream.match(/^-?0(?![\dx])/i)
        intLiteral = true
      if intLiteral
        return 'number'
    # Handle strings
    if stream.match(stringPrefixes)
      state.tokenize = tokenFactory(stream.current(), false, 'string')
      return state.tokenize(stream, state)
    # Handle regex literals
    if stream.match(regexPrefixes)
      if stream.current() != '/' or stream.match(/^.*\//, false)
        # prevent highlight of division
        state.tokenize = tokenFactory(stream.current(), true, 'string-2')
        return state.tokenize(stream, state)
      else
        stream.backUp 1
    # Handle operators and delimiters
    if stream.match(operators) or stream.match(wordOperators)
      return 'operator'
    if stream.match(delimiters)
      return 'punctuation'
    if stream.match(constants)
      return 'atom'
    if stream.match(atProp) or state.prop and stream.match(identifiers)
      return 'property'
    if stream.match(keywords)
      return 'keyword'
    if stream.match(identifiers)
      return 'variable'
    # Handle non-detected items
    stream.next()
    ERRORCLASS

  tokenFactory = (delimiter, singleline, outclass) ->
    (stream, state) ->
      while !stream.eol()
        stream.eatWhile /[^'"\/\\]/
        if stream.eat('\\')
          stream.next()
          if singleline and stream.eol()
            return outclass
        else if stream.match(delimiter)
          state.tokenize = tokenBase
          return outclass
        else
          stream.eat /['"\/]/
      if singleline
        if parserConf.singleLineStringErrors
          outclass = ERRORCLASS
        else
          state.tokenize = tokenBase
      outclass

  longComment = (stream, state) ->
    while !stream.eol()
      stream.eatWhile /[^#]/
      if stream.match('###')
        state.tokenize = tokenBase
        break
      stream.eatWhile '#'
    'comment'

  indent = (stream, state, type) ->
    type = type or 'coffee'
    offset = 0
    align = false
    alignOffset = null
    scope = state.scope
    while scope
      if scope.type == 'coffee' or scope.type == '}'
        offset = scope.offset + conf.indentUnit
        break
      scope = scope.prev
    if type != 'coffee'
      align = null
      alignOffset = stream.column() + stream.current().length
    else if state.scope.align
      state.scope.align = false
    state.scope =
      offset: offset
      type: type
      prev: state.scope
      align: align
      alignOffset: alignOffset
    return

  dedent = (stream, state) ->
    if !state.scope.prev
      return
    if state.scope.type == 'coffee'
      _indent = stream.indentation()
      matched = false
      scope = state.scope
      while scope
        if _indent == scope.offset
          matched = true
          break
        scope = scope.prev
      if !matched
        return true
      while state.scope.prev and state.scope.offset != _indent
        state.scope = state.scope.prev
      false
    else
      state.scope = state.scope.prev
      false

  tokenLexer = (stream, state) ->
    style = state.tokenize(stream, state)
    current = stream.current()
    # Handle scope changes.
    if current == 'return'
      state.dedent = true
    if (current == '->' or current == '=>') and stream.eol() or style == 'indent'
      indent stream, state
    delimiter_index = '[({'.indexOf(current)
    if delimiter_index != -1
      indent stream, state, '])}'.slice(delimiter_index, delimiter_index + 1)
    if indentKeywords.exec(current)
      indent stream, state
    if current == 'then'
      dedent stream, state
    if style == 'dedent'
      if dedent(stream, state)
        return ERRORCLASS
    delimiter_index = '])}'.indexOf(current)
    if delimiter_index != -1
      while state.scope.type == 'coffee' and state.scope.prev
        state.scope = state.scope.prev
      if state.scope.type == current
        state.scope = state.scope.prev
    if state.dedent and stream.eol()
      if state.scope.type == 'coffee' and state.scope.prev
        state.scope = state.scope.prev
      state.dedent = false
    style


  external = 
    startState: (basecolumn) ->
      {
        tokenize: tokenBase
        scope:
          offset: basecolumn or 0
          type: 'coffee'
          prev: null
          align: false
        prop: false
        dedent: 0
      }
    token: (stream, state) ->
      fillAlign = state.scope.align == null and state.scope
      if fillAlign and stream.sol()
        fillAlign.align = false
      style = tokenLexer(stream, state)
      if style and style != 'comment'
        if fillAlign
          fillAlign.align = true
        state.prop = style == 'punctuation' and stream.current() == '.'
      style
    indent: (state, text) ->
      if state.tokenize != tokenBase
        return 0
      scope = state.scope
      closer = text and '])}'.indexOf(text.charAt(0)) > -1
      if closer
        while scope.type == 'coffee' and scope.prev
          scope = scope.prev
      closes = closer and scope.type == text.charAt(0)
      if scope.align
        scope.alignOffset - (if closes then 1 else 0)
      else
        (if closes then scope.prev else scope).offset
    lineComment: '#'
    fold: 'indent'
  external
CodeMirror.defineMIME 'text/x-coffeescript', 'coffeescript'
CodeMirror.defineMIME 'text/coffeescript', 'coffeescript'

