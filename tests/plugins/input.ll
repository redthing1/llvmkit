define i32 @add(i32 %a, i32 %b) noinline {
  %sum = add i32 %a, %b
  ret i32 %sum
}

define i32 @ten_ops(i32 %a) noinline {
  %v1 = add i32 %a, 1
  %v2 = add i32 %v1, 2
  %v3 = add i32 %v2, 3
  %v4 = add i32 %v3, 4
  %v5 = add i32 %v4, 5
  %v6 = add i32 %v5, 6
  %v7 = add i32 %v6, 7
  %v8 = add i32 %v7, 8
  %v9 = add i32 %v8, 9
  ret i32 %v9
}

define i32 @caller(i32 %a) noinline {
  %v = call i32 @add(i32 %a, i32 1)
  %r = add i32 %v, 2
  ret i32 %r
}
