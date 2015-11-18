// Generated by CoffeeScript 1.9.1
(function() {
  var Pos, addPrefix, addPrefixMap, addToRing, byChar, byExpr, byLine, byPage, byParagraph, bySentence, byWord, clearMark, clearPrefix, findEnd, getFromRing, getInput, getPrefix, growRingTop, i, keyMap, kill, killRegion, killRing, killTo, lastKill, maybeClearPrefix, maybeDuplicateInput, maybeRemovePrefixMap, move, operateOnWord, popFromRing, posEq, prefixMap, prefixPreservingKeys, quit, regPrefix, repeated, setMark, toEnclosingExpr;
  Pos = CodeMirror.Pos;
  byChar = function(cm, pos, dir) {
    return cm.findPosH(pos, dir, 'char', true);
  };
  byWord = function(cm, pos, dir) {
    return cm.findPosH(pos, dir, 'word', true);
  };
  byLine = function(cm, pos, dir) {
    return cm.findPosV(pos, dir, 'line', cm.doc.sel.goalColumn);
  };
  byPage = function(cm, pos, dir) {
    return cm.findPosV(pos, dir, 'page', cm.doc.sel.goalColumn);
  };
  byParagraph = function(cm, pos, dir) {
    var fst, hasText, line, lst, num, sawText;
    num = pos.line;
    line = cm.getLine(num);
    sawText = /\S/.test(dir < 0 ? line.slice(0, pos.ch) : line.slice(pos.ch));
    fst = cm.firstLine();
    lst = cm.lastLine();
    while (true) {
      num += dir;
      if (num < fst || num > lst) {
        return cm.clipPos(Pos(num - dir, dir < 0 ? 0 : null));
      }
      line = cm.getLine(num);
      hasText = /\S/.test(line);
      if (hasText) {
        sawText = true;
      } else if (sawText) {
        return Pos(num, 0);
      }
    }
  };
  bySentence = function(cm, pos, dir) {
    var ch, line, next, sawWord, text;
    line = pos.line;
    ch = pos.ch;
    text = cm.getLine(pos.line);
    sawWord = false;
    while (true) {
      next = text.charAt(ch + (dir < 0 ? -1 : 0));
      if (!next) {
        if (line === (dir < 0 ? cm.firstLine() : cm.lastLine())) {
          return Pos(line, ch);
        }
        text = cm.getLine(line + dir);
        if (!/\S/.test(text)) {
          return Pos(line, ch);
        }
        line += dir;
        ch = dir < 0 ? text.length : 0;
        continue;
      }
      if (sawWord && /[!?.]/.test(next)) {
        return Pos(line, ch + (dir > 0 ? 1 : 0));
      }
      if (!sawWord) {
        sawWord = /\w/.test(next);
      }
      ch += dir;
    }
  };
  byExpr = function(cm, pos, dir) {
    var after, first, newPos, token, wrap;
    wrap = void 0;
    if (cm.findMatchingBracket && (wrap = cm.findMatchingBracket(pos, true)) && wrap.match && (wrap.forward ? 1 : -1) === dir) {
      if (dir > 0) {
        return Pos(wrap.to.line, wrap.to.ch + 1);
      } else {
        return wrap.to;
      }
    }
    first = true;
    while (true) {
      token = cm.getTokenAt(pos);
      after = Pos(pos.line, dir < 0 ? token.start : token.end);
      if (first && dir > 0 && token.end === pos.ch || !/\w/.test(token.string)) {
        newPos = cm.findPosH(after, dir, 'char');
        if (posEq(after, newPos)) {
          return pos;
        } else {
          pos = newPos;
        }
      } else {
        return after;
      }
      first = false;
    }
  };
  repeated = function(cmd) {
    var f;
    f = typeof cmd === 'string' ? (function(cm) {
      cm.execCommand(cmd);
    }) : cmd;
    return function(cm) {
      var i, prefix;
      prefix = getPrefix(cm);
      f(cm);
      i = 1;
      while (i < prefix) {
        f(cm);
        ++i;
      }
    };
  };
  findEnd = function(cm, pos, byy, dir) {
    var i, newPos, prefix;
    prefix = getPrefix(cm);
    if (prefix < 0) {
      dir = -dir;
      prefix = -prefix;
    }
    i = 0;
    while (i < prefix) {
      newPos = byy(cm, pos, dir);
      if (posEq(newPos, pos)) {
        break;
      }
      pos = newPos;
      ++i;
    }
    return pos;
  };
  move = function(byy, dir) {
    var f;
    f = function(cm) {
      cm.extendSelection(findEnd(cm, cm.getCursor(), byy, dir));
    };
    f.motion = true;
    return f;
  };
  killRing = [];
  lastKill = null;
  prefixPreservingKeys = {
    'Alt-G': true,
    'Ctrl-X': true,
    'Ctrl-Q': true,
    'Ctrl-U': true
  };
  prefixMap = {
    'Ctrl-G': clearPrefix
  };
  posEq = function(a, b) {
    return a.line === b.line && a.ch === b.ch;
  };
  addToRing = function(str) {
    killRing.push(str);
    if (killRing.length > 50) {
      killRing.shift();
    }
  };
  growRingTop = function(str) {
    if (!killRing.length) {
      return addToRing(str);
    }
    killRing[killRing.length - 1] += str;
  };
  getFromRing = function(n) {
    return killRing[killRing.length - (n ? Math.min(n, 1) : 1)] || '';
  };
  popFromRing = function() {
    if (killRing.length > 1) {
      killRing.pop();
    }
    return getFromRing();
  };
  kill = function(cm, from, to, mayGrow, text) {
    if (text === null) {
      text = cm.getRange(from, to);
    }
    if (mayGrow && lastKill && lastKill.cm === cm && posEq(from, lastKill.pos) && cm.isClean(lastKill.gen)) {
      growRingTop(text);
    } else {
      addToRing(text);
    }
    cm.replaceRange('', from, to, '+delete');
    if (mayGrow) {
      lastKill = {
        cm: cm,
        pos: from,
        gen: cm.changeGeneration()
      };
    } else {
      lastKill = null;
    }
  };
  getPrefix = function(cm, precise) {
    var digits;
    digits = cm.state.emacsPrefix;
    if (!digits) {
      if (precise) {
        return null;
      } else {
        return 1;
      }
    }
    clearPrefix(cm);
    if (digits === '-') {
      return -1;
    } else {
      return Number(digits);
    }
  };
  killTo = function(cm, byy, dir) {
    var cursor, i, selections;
    selections = cm.listSelections();
    cursor = void 0;
    i = selections.length;
    while (i--) {
      cursor = selections[i].head;
      kill(cm, cursor, findEnd(cm, cursor, byy, dir), true);
    }
  };
  killRegion = function(cm) {
    var i, selection, selections;
    if (cm.somethingSelected()) {
      selections = cm.listSelections();
      selection = void 0;
      i = selections.length;
      while (i--) {
        selection = selections[i];
        kill(cm, selection.anchor, selection.head);
      }
      return true;
    }
  };
  addPrefix = function(cm, digit) {
    if (cm.state.emacsPrefix) {
      if (digit !== '-') {
        cm.state.emacsPrefix += digit;
      }
      return;
    }
    cm.state.emacsPrefix = digit;
    cm.on('keyHandled', maybeClearPrefix);
    cm.on('inputRead', maybeDuplicateInput);
  };
  maybeClearPrefix = function(cm, arg) {
    if (!cm.state.emacsPrefixMap && !prefixPreservingKeys.hasOwnProperty(arg)) {
      clearPrefix(cm);
    }
  };
  clearPrefix = function(cm) {
    cm.state.emacsPrefix = null;
    cm.off('keyHandled', maybeClearPrefix);
    cm.off('inputRead', maybeDuplicateInput);
  };
  maybeDuplicateInput = function(cm, event) {
    var dup, i, one, txt;
    dup = getPrefix(cm);
    if (dup > 1 && event.origin === '+input') {
      one = event.text.join('\n');
      txt = '';
      i = 1;
      while (i < dup) {
        txt += one;
        ++i;
      }
      cm.replaceSelection(txt);
    }
  };
  addPrefixMap = function(cm) {
    cm.state.emacsPrefixMap = true;
    cm.addKeyMap(prefixMap);
    cm.on('keyHandled', maybeRemovePrefixMap);
    cm.on('inputRead', maybeRemovePrefixMap);
  };
  maybeRemovePrefixMap = function(cm, arg) {
    if (typeof arg === 'string' && (/^\d$/.test(arg) || arg === 'Ctrl-U')) {
      return;
    }
    cm.removeKeyMap(prefixMap);
    cm.state.emacsPrefixMap = false;
    cm.off('keyHandled', maybeRemovePrefixMap);
    cm.off('inputRead', maybeRemovePrefixMap);
  };
  setMark = function(cm) {
    console.log("setmark");
    cm.setCursor(cm.getCursor());
    cm.setExtending(!cm.getExtending());
    cm.on('change', function() {
      cm.setExtending(false);
    });
  };
  clearMark = function(cm) {
    cm.setExtending(false);
    cm.setCursor(cm.getCursor());
  };
  getInput = function(cm, msg, f) {
    if (cm.openDialog) {
      cm.openDialog(msg + ': <input type="text" style="width: 10em"/>', f, {
        bottom: true
      });
    } else {
      f(prompt(msg, ''));
    }
  };
  operateOnWord = function(cm, op) {
    var end, start;
    start = cm.getCursor();
    end = cm.findPosH(start, 1, 'word');
    cm.replaceRange(op(cm.getRange(start, end)), start, end);
    cm.setCursor(end);
  };
  toEnclosingExpr = function(cm) {
    var ch;
    var ch, i, line, pos, stack, text;
    pos = cm.getCursor();
    line = pos.line;
    ch = pos.ch;
    stack = [];
    while (line >= cm.firstLine()) {
      text = cm.getLine(line);
      i = ch === null ? text.length : ch;
      while (i > 0) {
        ch = text.charAt(--i);
        if (ch === ')') {
          stack.push('(');
        } else if (ch === ']') {
          stack.push('[');
        } else if (ch === '}') {
          stack.push('{');
        } else if (/[\(\{\[]/.test(ch) && (!stack.length || stack.pop() !== ch)) {
          return cm.extendSelection(Pos(line, i));
        }
      }
      --line;
      ch = null;
    }
  };
  quit = function(cm) {
    cm.execCommand('clearSearch');
    clearMark(cm);
  };
  keyMap = CodeMirror.keyMap.emacs = CodeMirror.normalizeKeyMap({
    'Ctrl-W': function(cm) {
      kill(cm, cm.getCursor('start'), cm.getCursor('end'));
    },
    'Ctrl-P': function(cm) {
      kill(cm, cm.getCursor('start'), cm.getCursor('end'));
    },
    'Ctrl-K': repeated(function(cm) {
      var end, start, text;
      start = cm.getCursor();
      end = cm.clipPos(Pos(start.line));
      text = cm.getRange(start, end);
      if (!/\S/.test(text)) {
        text += '\n';
        end = Pos(start.line + 1, 0);
      }
      kill(cm, start, end, true, text);
    }),
    'Alt-W': function(cm) {
      addToRing(cm.getSelection());
      clearMark(cm);
    },
    'Ctrl-Y': function(cm) {
      var start;
      start = cm.getCursor();
      cm.replaceRange(getFromRing(getPrefix(cm)), start, start, 'paste');
      cm.setSelection(start, cm.getCursor());
    },
    'Alt-Y': function(cm) {
      cm.replaceSelection(popFromRing(), 'around', 'paste');
    },
    'Ctrl-Space': setMark,
    'Ctrl-Shift-2': setMark,
    'Ctrl-F': move(byChar, 1),
    'Ctrl-B': move(byChar, -1),
    'Right': move(byChar, 1),
    'Left': move(byChar, -1),
    'Ctrl-D': function(cm) {
      killTo(cm, byChar, 1);
    },
    'Delete': function(cm) {
      killRegion(cm) || killTo(cm, byChar, 1);
    },
    'Ctrl-H': function(cm) {
      killTo(cm, byChar, -1);
    },
    'Backspace': function(cm) {
      killRegion(cm) || killTo(cm, byChar, -1);
    },
    'Alt-F': move(byWord, 1),
    'Alt-B': move(byWord, -1),
    'Alt-D': function(cm) {
      killTo(cm, byWord, 1);
    },
    'Alt-Backspace': function(cm) {
      killTo(cm, byWord, -1);
    },
    'Ctrl-N': move(byLine, 1),
    'Ctrl-P': move(byLine, -1),
    'Down': move(byLine, 1),
    'Up': move(byLine, -1),
    'Ctrl-A': 'goLineStart',
    'Ctrl-E': 'goLineEnd',
    'End': 'goDocEnd',
    'Home': 'goDocStart',
    'Alt-V': move(byPage, -1),
    'Ctrl-V': move(byPage, 1),
    'PageUp': move(byPage, -1),
    'PageDown': move(byPage, 1),
    'Ctrl-Up': move(byParagraph, -1),
    'Ctrl-Down': move(byParagraph, 1),
    'Alt-A': move(bySentence, -1),
    'Alt-E': move(bySentence, 1),
    'Alt-K': function(cm) {
      killTo(cm, bySentence, 1);
    },
    'Ctrl-Alt-K': function(cm) {
      killTo(cm, byExpr, 1);
    },
    'Ctrl-Alt-Backspace': function(cm) {
      killTo(cm, byExpr, -1);
    },
    'Ctrl-Alt-F': move(byExpr, 1),
    'Ctrl-Alt-B': move(byExpr, -1),
    'Shift-Ctrl-Alt-2': function(cm) {
      var cursor;
      cursor = cm.getCursor();
      cm.setSelection(findEnd(cm, cursor, byExpr, 1), cursor);
    },
    'Ctrl-Alt-T': function(cm) {
      var leftEnd, leftStart, rightEnd, rightStart;
      leftStart = byExpr(cm, cm.getCursor(), -1);
      leftEnd = byExpr(cm, leftStart, 1);
      rightEnd = byExpr(cm, leftEnd, 1);
      rightStart = byExpr(cm, rightEnd, -1);
      cm.replaceRange(cm.getRange(rightStart, rightEnd) + cm.getRange(leftEnd, rightStart) + cm.getRange(leftStart, leftEnd), leftStart, rightEnd);
    },
    'Ctrl-Alt-U': repeated(toEnclosingExpr),
    'Alt-Space': function(cm) {
      var from, pos, text, to;
      pos = cm.getCursor();
      from = pos.ch;
      to = pos.ch;
      text = cm.getLine(pos.line);
      while (from && /\s/.test(text.charAt(from - 1))) {
        --from;
      }
      while (to < text.length && /\s/.test(text.charAt(to))) {
        ++to;
      }
      cm.replaceRange(' ', Pos(pos.line, from), Pos(pos.line, to));
    },
    'Ctrl-O': repeated(function(cm) {
      cm.replaceSelection('\n', 'start');
    }),
    'Ctrl-T': repeated(function(cm) {
      cm.execCommand('transposeChars');
    }),
    'Alt-C': repeated(function(cm) {
      operateOnWord(cm, function(w) {
        var letter;
        letter = w.search(/\w/);
        if (letter === -1) {
          return w;
        }
        return w.slice(0, letter) + w.charAt(letter).toUpperCase() + w.slice(letter + 1).toLowerCase();
      });
    }),
    'Alt-U': repeated(function(cm) {
      operateOnWord(cm, function(w) {
        return w.toUpperCase();
      });
    }),
    'Alt-L': repeated(function(cm) {
      operateOnWord(cm, function(w) {
        return w.toLowerCase();
      });
    }),
    'Alt-;': 'toggleComment',
    'Ctrl-/': repeated('undo'),
    'Shift-Ctrl--': repeated('undo'),
    'Ctrl-Z': repeated('undo'),
    'Cmd-Z': repeated('undo'),
    'Shift-Alt-,': 'goDocStart',
    'Shift-Alt-.': 'goDocEnd',
    'Ctrl-S': 'findNext',
    'Ctrl-R': 'findPrev',
    'Ctrl-G': quit,
    'Shift-Alt-5': 'replace',
    'Alt-/': 'autocomplete',
    'Ctrl-J': 'newlineAndIndent',
    'Enter': 'newlineAndIndent',
    'Shift-tab': 'indentLess',
    'Tab': function(cm) {
      if (cm.somethingSelected()) {
        cm.indentSelection('add');
      } else {
        cm.indentSelection('smart');
      }
    },
    'Alt-G G': function(cm) {
      var prefix;
      prefix = getPrefix(cm, true);
      if (prefix !== null && prefix > 0) {
        return cm.setCursor(prefix - 1);
      }
      getInput(cm, 'Goto line', function(str) {
        var num;
        num = void 0;
        if (str && !isNaN(num = Number(str)) && num === (num | 0) && num > 0) {
          cm.setCursor(num - 1);
        }
      });
    },
    'Ctrl-X Tab': function(cm) {
      cm.indentSelection(getPrefix(cm, true) || cm.getOption('indentUnit'));
    },
    'Ctrl-X Ctrl-X': function(cm) {
      cm.setSelection(cm.getCursor('head'), cm.getCursor('anchor'));
    },
    'Ctrl-X Ctrl-S': 'save',
    'Ctrl-X Ctrl-W': 'save',
    'Ctrl-X S': 'saveAll',
    'Ctrl-X F': 'open',
    'Ctrl-X U': repeated('undo'),
    'Ctrl-X K': 'close',
    'Ctrl-X Delete': function(cm) {
      kill(cm, cm.getCursor(), bySentence(cm, cm.getCursor(), 1), true);
    },
    'Ctrl-X H': 'selectAll',
    'Ctrl-Q Tab': repeated('insertTab'),
    'Ctrl-U': addPrefixMap
  });
  regPrefix = function(d) {
    prefixMap[d] = function(cm) {
      addPrefix(cm, d);
    };
    keyMap['Ctrl-' + d] = function(cm) {
      addPrefix(cm, d);
    };
    prefixPreservingKeys['Ctrl-' + d] = true;
  };
  i = 0;
  while (i < 10) {
    regPrefix(String(i));
    ++i;
  }
  return regPrefix('-');
})();
