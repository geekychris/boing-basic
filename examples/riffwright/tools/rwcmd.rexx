/* rwcmd.rexx - send one command to Riffwright's ARexx port and print the answer */
parse arg cmd
options results
address RIFFWRIGHT cmd
say 'RC=' || rc 'RESULT=' || result
