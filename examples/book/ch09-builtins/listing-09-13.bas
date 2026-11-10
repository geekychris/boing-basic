Dim amounts As Variant, a As Variant
amounts = Array(12.5, -3, 0)
For Each a In amounts
    Print Format(a, "0.00;(0.00);\n\i\l")
Next
