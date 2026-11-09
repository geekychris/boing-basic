/* arexx-test.rexx - talk to a running Tincture through its ARexx port (tools/guest.py arexx) */
OPTIONS RESULTS
ADDRESS 'TINCTURE'
'VERSION'
SAY 'version' RESULT
'NEW 64 48'
'COLOR 255 0 0'
'BOX 0 0 10 10'
'GETPIXEL 5 5'
SAY 'pixel' RESULT
'LAYER ADD Ink'
'INFO'
SAY 'info' RESULT
'FROB'
SAY 'rc' RC
'QUIT'
SAY 'done'
