# Exercise 1: Console programs

In this exercise you write programs that talk to you in a Shell window: they print text, ask
questions and act on your answers. You build a number-guessing game, a times-table quiz and a
word counter, and then put all three into one project with a menu.

**Goal:** a "Console Toolbox" program with a menu of three small programs.

**What you will learn:**

- `Print`, and how numbers are printed
- reading answers with `Input` and `Line Input`
- variables, `Dim` and `Option Explicit`
- decisions with `If` and `Select Case`
- loops with `Do ... Loop` and `For ... Next`
- random numbers with `Rnd` and `Randomize`
- your own `Function`s and `Sub`s
- string functions: `Split`, `Len`, `Mid`, `UCase`, `LCase`, `InStr`, `Left`, `Format`
- a project (`.bbp`) made of several modules

The full solution is in `examples/book/ex01-console/`.

## Step 1: Print

Make a drawer for the exercise, and in it a text file `hello.bas` with any text editor (or
AmiForge, see "Running it" below):

<!-- run -->
```basic
' My first program
Print "Hello, Amiga!"
Print "2 + 3 ="; 2 + 3
Print "Seven squared is " & 7 * 7
```

```output
Hello, Amiga!
2 + 3 = 5 
Seven squared is 49
```

Run it from a Shell in that drawer:

```sh
boing run hello.bas
```

A few things to notice:

- A line that starts with `'` is a comment: Boing BASIC ignores it.
- `;` between items prints them one after the other. `&` joins two strings into one.
- `Print` puts a space before a positive number and one after every number (the space before
  is where a minus sign would go). That is why the second line ends with `5 ` and has a space
  after `=`. When you join a number to a string with `&`, it becomes text first and gets no
  extra spaces, as in the third line.

## Step 2: Asking questions

`Line Input` reads a whole line of text into a String variable. `Input` reads a number (or
several, separated by commas). `Input "prompt"; variable` prints the prompt followed by `? `. Here is a program, and what it
prints when you type `Ann` and `12` (in the output blocks of these exercises the answers you
type are left out: they are not part of what the program prints):

<!-- run stdin="Ann\n12" -->
```basic
Option Explicit
Dim yourName As String, age As Long

Print "What is your name? ";
Line Input yourName
Input "How old are you"; age
If age >= 18 Then
    Print "Hello, " & yourName & ". You are a grown-up."
Else
    Print "Hello, " & yourName & ". In"; 18 - age; "years you will be 18."
End If
```

```output
What is your name? How old are you? Hello, Ann. In 6 years you will be 18.
```

- `Option Explicit` at the top makes Boing BASIC insist that every variable is declared with
  `Dim`. A misspelt name is then an error when the program is checked, not a silent new
  variable. Use it in every program.
- `Dim yourName As String, age As Long` declares two variables: a String (text) and a Long
  (a whole number, 32 bits). Other types you will meet are `Integer` (16 bits), `Double`
  (a number with decimals) and `Boolean` (`True` or `False`).
- A `Print` that ends with `;` leaves the cursor on the same line, so the answer is typed
  after the question.
- `Line Input` needs a String variable. `Input` into a Long gives run-time error 13 (Type
  mismatch) if you type something that is not a number. Step 6 shows a safer way.

## Step 3: A guessing game, with a loop

The computer picks a number from 1 to 100 and you guess it. `Rnd` gives a random number from 0
up to (but not including) 1, so `Int(Rnd * 100) + 1` is a whole number from 1 to 100.

<!-- run stdin="50\n25\n37\n43\n46" -->
```basic
Option Explicit
Dim secret As Long, guess As Long, tries As Long

Randomize 7                         ' a fixed seed: the same number every run
secret = Int(Rnd * 100) + 1         ' Rnd is from 0 up to (not including) 1
Print "I am thinking of a number from 1 to 100."
Do
    Input "Your guess"; guess
    tries = tries + 1
    If guess < secret Then
        Print "Too low."
    ElseIf guess > secret Then
        Print "Too high."
    End If
Loop Until guess = secret
Print "Yes! You needed"; tries; "tries."
```

```output
I am thinking of a number from 1 to 100.
Your guess? Too high.
Your guess? Too low.
Your guess? Too low.
Your guess? Too low.
Your guess? Yes! You needed 5 tries.
```

- `Do ... Loop Until condition` repeats the lines between them until the condition is true.
  You can also write `Do While condition ... Loop`, or leave the condition out and leave the
  loop with `Exit Do`.
- `If ... ElseIf ... End If` picks the first branch whose condition is true.
- `Randomize 7` starts the random numbers from a fixed "seed", so the secret number is 46 on
  every run. That is handy while you test. `Randomize` on its own takes the seed from the
  clock, and the game is different every time.
- Variables start at 0 (Strings at `""`), so `tries` needs no first value.

## Step 4: Functions and Select Case: a times-table quiz

As a program grows, give each job its own procedure. A `Function` returns a value (assign it
to the function's name); a `Sub` just does something. When a program has procedures, the
program starts in `Sub Main`.

<!-- run stdin="7\n42\n84\n20\n70" -->
```basic
Option Explicit

Const QUESTIONS = 4

Sub Main()
    Dim table As Long, i As Long, score As Long

    Randomize 7
    Input "Which table"; table
    For i = 1 To QUESTIONS
        If AskQuestion(RandomNumber(2, 12), table) Then score = score + 1
    Next i
    Print "You scored"; score; "out of"; QUESTIONS; "- "; Praise(score)
End Sub

' A random whole number from low to high.
Function RandomNumber(low As Long, high As Long) As Long
    RandomNumber = Int(Rnd * (high - low + 1)) + low
End Function

' Ask "a x b"; True when the answer is right.
Function AskQuestion(a As Long, b As Long) As Boolean
    Dim answer As Long
    Print a; "x"; b;
    Input answer
    If answer = a * b Then
        Print "Right!"
        AskQuestion = True
    Else
        Print "No, it is"; a * b
    End If
End Function

Function Praise(score As Long) As String
    Select Case score
    Case QUESTIONS: Praise = "perfect!"
    Case Is >= QUESTIONS \ 2: Praise = "not bad."
    Case Else: Praise = "keep practising."
    End Select
End Function
```

```output
Which table?  6 x 7 ? Right!
 12 x 7 ? Right!
 3 x 7 ? No, it is 21 
 10 x 7 ? Right!
You scored 3 out of 4 - not bad.
```

- `Const QUESTIONS = 4` names a value that never changes. Change it in one place to make a
  longer quiz.
- `For i = 1 To QUESTIONS ... Next i` counts `i` from 1 to 4.
- `Select Case` compares one value with a list of cases and runs the first that matches. A
  case can be a value (`Case 3`), a list (`Case 6, 7`), a range (`Case 2 To 5`), a comparison
  (`Case Is >= 2`) or `Case Else`. A `:` lets you put a short statement on the same line.
- `\` divides and drops the remainder: `QUESTIONS \ 2` is 2.
- `Dim answer` inside `AskQuestion` is a local variable: it exists only while the function
  runs.

## Step 5: Strings: a word counter

`Split(text, " ")` cuts a string at every space and gives an array of the pieces, numbered
from 0 to `UBound(array)`.

<!-- run stdin="Boing BASIC  runs on AmigaOS" -->
```basic
Option Explicit
Dim lineText As String, words() As String
Dim i As Long, wordCount As Long, longest As String

Print "Type a line of text: ";
Line Input lineText
words = Split(lineText, " ")         ' an array: words(0) to words(UBound(words))
For i = 0 To UBound(words)
    If words(i) <> "" Then           ' two spaces in a row give an empty "word"
        wordCount = wordCount + 1
        If Len(words(i)) > Len(longest) Then longest = words(i)
    End If
Next i
Print "Words:"; wordCount
Print "Longest: " & longest & " (" & Len(longest) & " letters)"
Print "Shouting: " & UCase(lineText)
Print "Backwards: " & StrReverse(lineText)
Print "First word: " & Left(lineText, InStr(lineText & " ", " ") - 1)
```

```output
Type a line of text: Words: 5 
Longest: AmigaOS (7 letters)
Shouting: BOING BASIC  RUNS ON AMIGAOS
Backwards: SOagimA no snur  CISAB gnioB
First word: Boing
```

| Function | Gives |
|---|---|
| `Len(s)` | the number of characters |
| `Left(s, n)`, `Right(s, n)` | the first / last n characters |
| `Mid(s, start, n)` | n characters from position `start` (the first character is 1) |
| `InStr(s, find)` | where `find` first appears in `s`, 0 if it does not |
| `UCase(s)`, `LCase(s)` | upper / lower case |
| `Trim(s)` | `s` without spaces at either end |
| `StrReverse(s)` | `s` backwards |
| `Split(s, sep)` | an array of the parts of `s` between the separators |

The full solution goes further: it reads lines until you type an empty one, counts the
letters, and cleans each word with a small function that keeps only letters, digits and
apostrophes, using `Mid` and a `Select Case` with ranges of characters (`Case "a" To "z"`).

## Step 6: One project, several modules

Now put the three programs together. A **project** is a `.bbp` text file that lists the files
of a program. Each `Module=` line is a `.bas` file; `Startup=Sub Main` says where it starts:

```ini
# Boing BASIC project: exercise 1 of the user manual, a console toolbox
# (a number-guessing game, a times-table quiz and a word counter).
Name=Console
Startup=Sub Main
Module=Main.bas
Module=Answers.bas
Module=Guess.bas
Module=Quiz.bas
Module=Words.bas
```

The procedures of one module can call the `Public` procedures of the others. `Main.bas` is
the menu: a `Do` loop around a `Select Case` on your choice.

<!-- project: examples/book/ex01-console/Console.bbp -->
```basic
Sub Main()
    Dim choice As String

    If InStr(Command(), "--random") > 0 Then
        Randomize                 ' seed from the clock: a new game every time
    Else
        Randomize 7               ' a fixed seed: the same numbers every run
    End If

    Print "Console Toolbox"
    Do
        Print
        Print "1) Guess the number"
        Print "2) Times-table quiz"
        Print "3) Count words"
        Print "0) Quit"
        choice = Ask("Your choice")
        Select Case choice
        Case "1": GuessGame
        Case "2": TablesQuiz
        Case "3": CountWords
        Case "0", "q", "Q": Exit Do
        Case Else: Print "Please type 0, 1, 2 or 3."
        End Select
    Loop
    Print "Goodbye!"
End Sub
```

`Command()` is the text given after the program's name when it was started, so
`boing run Console.bbp --random` gives a new game each time.

`Answers.bas` has the functions that read answers. `AskNumber` keeps asking until the answer
is a whole number in range, so a typing mistake no longer stops the program with error 13:

<!-- project: examples/book/ex01-console/Console.bbp -->
```basic
' Ask until the answer is a whole number from low to high.
Public Function AskNumber(prompt As String, low As Long, high As Long) As Long
    Dim answer As String
    Do
        answer = Ask(prompt)
        If IsNumeric(answer) Then
            If Val(answer) >= low And Val(answer) <= high And Val(answer) = Int(Val(answer)) Then
                AskNumber = Val(answer)
                Exit Function
            End If
        End If
        Print "Please type a whole number from " & low & " to " & high & "."
    Loop
End Function
```

`IsNumeric` says whether a string is a number, and `Val` turns it into one. `Exit Function`
leaves the function at once, with the value set just before.

`Guess.bas` gives hints with a `Select Case` on how far away the guess is:

<!-- project: examples/book/ex01-console/Console.bbp -->
```basic
Private Function Hint(distance As Long) As String
    Select Case distance
    Case 1 To 3: Hint = "very close!"
    Case 4 To 10: Hint = "close."
    Case 11 To 25: Hint = "not far."
    Case Else: Hint = "far away."
    End Select
End Function
```

`Private` procedures can only be called from their own module, so `Hint` in `Guess.bas` and
another `Hint` elsewhere would not clash.

One rule to remember: a module's name (its file name without `.bas`) is a name in the
program too, so a module may not have the same name as one of its procedures. A module
`Ask.bas` holding `Function Ask` gives the error "'Ask' is a type or module name, not a
value"; that is why the module is called `Answers.bas`.

## Running it

From a Shell, in the solution's drawer:

```sh
boing run Console.bbp
boing run Console.bbp --random
```

`boing run` checks the program and starts it at once in the interpreter. To make a native
program instead, which starts faster and runs much faster:

```sh
boing build Console.bbp -o Console
Console
```

`boing check Console.bbp` only checks the program and lists its errors as
`file:line:column: error: ...`.

In AmiForge: choose **New Project from Template** and **Boing BASIC Console App**. It makes a
project with a `.bbp` and a `Main.bas` holding a `Sub Main`. Add the other modules to the
project (AmiForge adds a `Module=` line to the `.bbp` for each), then press **Ctrl-F5** (Run):
AmiForge checks the program and runs it in a console window. Program arguments such as
`--random` go in **Project > Settings**. **F7** (Build) makes the native program. To use the
solution as it is, open `examples/book/ex01-console/Console.bbp` with **Open Project**.

The solution's drawer also has `input.txt`, a set of answers, and `expected.out`, what the
program prints for them. The manual's tests run `boing run Console.bbp < input.txt` and
compare the output with `expected.out`. You can do the same in a Shell to test your own
version.

## Try this

1. Make the guessing game count down: allow only 7 tries, and say "Out of tries!" and the
   number when they are used up.
2. Let the quiz ask questions from random tables (2 to 12) instead of one table, and time it
   with `Timer` (the seconds since midnight): print how long the quiz took.
3. In the word counter, count how many times each word appears and print the most common
   one. (Keep two arrays, one of words and one of counts, or wait for the `Collection` in
   [Exercise 2](02-adventure.md).)
4. Add a fourth menu entry: a temperature table that prints Celsius and Fahrenheit side by side
   for 0 to 100 in steps of 10, with `For ... Step 10` and `Format`.
5. Keep a best score for the guessing game in a file (see [Files](../10-files.md)) and
   congratulate the player who beats it.

## See also

- [Data, variables and types](../04-data.md), [Procedures](../05-procedures.md),
  [Control flow](../06-control-flow.md), [Built-in functions](../09-builtins.md)
- Next: [Exercise 2: A text adventure](02-adventure.md)
