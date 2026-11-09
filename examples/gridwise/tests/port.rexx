/* Gridwise's ARexx port, driven by the guest smoke test */
OPTIONS RESULTS
ADDRESS GRIDWISE
'GETCELL E8'
SAY 'rexx E8=' || RESULT
'SETCELL G1 =E8*2'
'GETCELL G1'
SAY 'rexx G1=' || RESULT
'VERSION'
SAY 'rexx version=' || RESULT
