/* Penwright's ARexx port, driven by the guest smoke test */
OPTIONS RESULTS
ADDRESS PENWRIGHT
'WORDCOUNT'
SAY 'rexx words=' || RESULT
'GETPARA 0'
SAY 'rexx para0=' || RESULT
'VERSION'
SAY 'rexx version=' || RESULT
