Const MAX_LIVES = 3
Const TITLE As String = "Boing Ball"
Const SPEED As Double = 2.5, DOUBLE_SPEED = SPEED * 2
Const MASK = &HFF00&, NEG = -MAX_LIVES
Print MAX_LIVES; TITLE; SPEED; DOUBLE_SPEED; MASK; NEG
Print TypeName(MAX_LIVES); " "; TypeName(DOUBLE_SPEED)
