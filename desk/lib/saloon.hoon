  ::
::::  Saloon:  Scientific ALgorithms in hOON
::
::  Transcendental functions library for Urbit.
::
::  Pure Hoon implementations are generally naive formally correct algorithms,
::  awaiting efficient jetting.
::
/-  ls=lagoon
/+  *lagoon,
    math
::                                                    ::
::::                    ++sa                          ::  (2v) vector/matrix ops
~%  %saloon  ..part  ~
|%
::  +sake: set +sa params
::
::    rnd: rounding mode
::    rtol: relative tolerance, use the correct bit width @r
::
++  sake
  |=  [inrnd=rounding-mode inrtol=@r]
  %*(. sa rnd inrnd, rtol inrtol)
::
++  sa
  ^|
  =+  [rnd=*rounding-mode rtol=`@r`0x1]
  ~/  %sa-core
  |%
  ::  innermost core of Saloon functionality
  ::  basically an implementation of /lib/math for Lagoon arrays
  +|  %uno
  ::
  ::  Comparison
  ::
  ::    +lth:  [$ray $ray] -> $ray
  ::
  ::  Returns the BOOLEAN comparison of two floating-point rays, less than
  ::    Examples
  ::      > (lth:sa:sa (ones:la:la [~[5 1] 5 %i754 ~]) (en-ray:la:la [~[5 1] 5 %i754 ~] ~[.1 .0 .1 .2 .0]))
  ::      [meta=[shape=~[5 1] bloq=5 kind=%i754 fxp=~] data=0x1.0000.0000.0000.0000.0000.0000.3f80.0000.0000.0000]
  ::      > ;;((list (list @rs)) data:(de-ray:la:la (lth:sa:sa (ones:la:la [~[5 1] 5 %i754 ~]) (en-ray:la:la [~[5 1] 5 %i754 ~] ~[.1 .0 .1 .2 .0]))))
  ::      [i=~[.0] t=[i=~[.0] t=~[~[.0] ~[.1] ~[.0]]]]
  ::  Source
  ++  lth  lth:(lake rnd)
  ::    +lte:  [$ray $ray] -> $ray
  ::
  ::  Returns the BOOLEAN comparison of two floating-point rays, less than or equal to
  ::    Examples
  ::      > (lte:sa:sa (ones:la:la [~[5 1] 5 %i754 ~]) (en-ray:la:la [~[5 1] 5 %i754 ~] ~[.1 .0 .1 .2 .0]))
  ::      [meta=[shape=~[5 1] bloq=5 kind=%i754 fxp=~] data=0x1.3f80.0000.0000.0000.3f80.0000.3f80.0000.0000.0000]
  ::      > ;;((list (list @rs)) data:(de-ray:la:la (lte:sa:sa (ones:la:la [~[5 1] 5 %i754 ~]) (en-ray:la:la [~[5 1] 5 %i754 ~] ~[.1 .0 .1 .2 .0]))))
  ::      [i=~[.1] t=[i=~[.0] t=~[~[.1] ~[.1] ~[.0]]]]
  ::  Source
  ++  lte  lte:(lake rnd)
  ::    +leq:  [$ray $ray] -> $ray
  ::
  ::  Returns the BOOLEAN comparison of two floating-point rays, less than or equal to
  ::  Alias for +lte.
  ::    Examples
  ::      > (leq:sa:sa (ones:la:la [~[5 1] 5 %i754 ~]) (en-ray:la:la [~[5 1] 5 %i754 ~] ~[.1 .0 .1 .2 .0]))
  ::      [meta=[shape=~[5 1] bloq=5 kind=%i754 fxp=~] data=0x1.3f80.0000.0000.0000.3f80.0000.3f80.0000.0000.0000]
  ::      > ;;((list (list @rs)) data:(de-ray:la:la (leq:sa:sa (ones:la:la [~[5 1] 5 %i754 ~]) (en-ray:la:la [~[5 1] 5 %i754 ~] ~[.1 .0 .1 .2 .0]))))
  ::      [i=~[.1] t=[i=~[.0] t=~[~[.1] ~[.1] ~[.0]]]]
  ::  Source
  ++  leq  lte:(lake rnd)
  ::    +equ:  [$ray $ray] -> $ray
  ::
  ::  Returns the BOOLEAN comparison of two floating-point rays, equal to
  ::    Examples
  ::      > (equ:la:la (ones:la:la [~[5 1] 5 %i754 ~]) (en-ray:la:la [~[5 1] 5 %i754 ~] ~[.1 .0 .1 .2 .0]))
  ::      [meta=[shape=~[5 1] bloq=5 kind=%i754 fxp=~] data=0x1.3f80.0000.0000.0000.3f80.0000.0000.0000.0000.0000]
  ::      > ;;((list (list @rs)) data:(de-ray:la:la (equ:la:la (ones:la:la [~[5 1] 5 %i754 ~]) (en-ray:la:la [~[5 1] 5 %i754 ~] ~[.1 .0 .1 .2 .0]))))
  ::      [i=~[.1] t=[i=~[.0] t=~[~[.1] ~[.0] ~[.0]]]]
  ::  Source
  ++  equ  equ:(lake rnd)
  ::    +gth:  [$ray $ray] -> $ray
  ::
  ::  Returns the BOOLEAN comparison of two floating-point rays, greater than
  ::    Examples
  ::      > (gth:sa:sa (ones:la:la [~[5 1] 5 %i754 ~]) (en-ray:la:la [~[5 1] 5 %i754 ~] ~[.1 .0 .1 .2 .0]))
  ::      [meta=[shape=~[5 1] bloq=5 kind=%i754 fxp=~] data=data=0x1.0000.0000.3f80.0000.0000.0000.0000.0000.3f80.0000]
  ::      > ;;((list (list @rs)) data:(de-ray:la:la (gth:sa:sa (ones:la:la [~[5 1] 5 %i754 ~]) (en-ray:la:la [~[5 1] 5 %i754 ~] ~[.1 .0 .1 .2 .0]))))
  ::      [i=~[.0] t=[i=~[.1] t=~[~[.0] ~[.0] ~[.1]]]]
  ::  Source
  ++  gth  gth:(lake rnd)
  ::    +gte:  [$ray $ray] -> $ray
  ::
  ::  Returns the BOOLEAN comparison of two floating-point rays, greater than or equal to
  ::    Examples
  ::      > (gte:sa:sa (ones:la:la [~[5 1] 5 %i754 ~]) (en-ray:la:la [~[5 1] 5 %i754 ~] ~[.1 .0 .1 .2 .0]))
  ::      [meta=[shape=~[5 1] bloq=5 kind=%i754 fxp=~] data=data=0x1.3f80.0000.3f80.0000.3f80.0000.0000.0000.3f80.0000]
  ::      > ;;((list (list @rs)) data:(de-ray:la:la (gte:sa:sa (ones:la:la [~[5 1] 5 %i754 ~]) (en-ray:la:la [~[5 1] 5 %i754 ~] ~[.1 .0 .1 .2 .0]))))
  ::      [i=~[.1] t=[i=~[.1] t=~[~[.1] ~[.0] ~[.1]]]]
  ::  Source
  ++  gte  gte:(lake rnd)
  ::    +geq:  [$ray $ray] -> $ray
  ::
  ::  Returns the BOOLEAN comparison of two floating-point rays, greater than or equal to
  ::  Alias for +gte.
  ::    Examples
  ::      > (geq:sa:sa (ones:la:la [~[5 1] 5 %i754 ~]) (en-ray:la:la [~[5 1] 5 %i754 ~] ~[.1 .0 .1 .2 .0]))
  ::      [meta=[shape=~[5 1] bloq=5 kind=%i754 fxp=~] data=data=0x1.3f80.0000.3f80.0000.3f80.0000.0000.0000.3f80.0000]
  ::      > ;;((list (list @rs)) data:(de-ray:la:la (geq:sa:sa (ones:la:la [~[5 1] 5 %i754 ~]) (en-ray:la:la [~[5 1] 5 %i754 ~] ~[.1 .0 .1 .2 .0]))))
  ::      [i=~[.1] t=[i=~[.1] t=~[~[.1] ~[.0] ~[.1]]]]
  ::  Source
  ++  geq  gte:(lake rnd)
  ::    +neq:  [$ray $ray] -> $ray
  ::
  ::  Returns the BOOLEAN comparison of two floating-point rays, equal to
  ::    Examples
  ::      > (neq:la:la (ones:la:la [~[5 1] 5 %i754 ~]) (en-ray:la:la [~[5 1] 5 %i754 ~] ~[.1 .0 .1 .2 .0]))
  ::      [meta=[shape=~[5 1] bloq=5 kind=%i754 fxp=~] data=0x1.0000.0000.3f80.0000.0000.0000.3f80.0000.3f80.0000]
  ::      > ;;((list (list @rs)) data:(de-ray:la:la (neq:la:la (ones:la:la [~[5 1] 5 %i754 ~]) (en-ray:la:la [~[5 1] 5 %i754 ~] ~[.1 .0 .1 .2 .0]))))
  ::      [i=~[.0] t=[i=~[.1] t=~[~[.0] ~[.1] ~[.1]]]]
  ::  Source
  ++  neq  neq:(lake rnd)
  ::    +is-close:  [$ray $ray] -> $ray
  ::
  ::  Returns the BOOLEAN comparison of two floating-point rays, close to
  ::    Examples
  ::      > (is-close:sa:sa (ones:la:la [~[5 1] 5 %i754 ~]) (en-ray:la:la [~[5 1] 5 %i754 ~] ~[.1 .0 .1 .2 .0]))
  ::      [meta=[shape=~[5 1] bloq=5 kind=%i754 fxp=~] data=0x1.3f80.0000.0000.0000.3f80.0000.3f80.0000.0000.0000.0000]
  ::      > ;;((list (list @rs)) data:(de-ray:la:la (is-close:sa:sa (ones:la:la [~[5 1] 5 %i754 ~]) (en-ray:la:la [~[5 1] 5 %i754 ~] ~[.1 .0 .1 .2 .0]))))
  ::      [i=~[.1] t=[i=~[.0] t=~[~[.1] ~[.1] ~[.0]]]
  ::  Source
  ++  is-close
    |=  [a=ray:ls b=ray:ls]
    ^-  ray:ls
    (is-close:(lake rnd) a b [0x0 rtol])
  ::    +all-close:  [$ray $ray] -> ?
  ::
  ::  Returns the LOOBEAN comparison of two floating-point rays, all close to
  ::    Examples
  ::      > (all-close:sa:sa (ones:la:la [~[5 1] 5 %i754 ~]) (en-ray:la:la [~[5 1] 5 %i754 ~] ~[.1 .0 .1 .2 .0]))
  ::      %.n
  ::      > (all-close:sa:sa (ones:la:la [~[5 1] 5 %i754 ~]) (ones:la:la [~[5 1] 5 %i754 ~]))
  ::      %.y
  ::  Source
  ++  all-close  all:(lake rnd)
  ::    +any-close:  [$ray $ray] -> ?
  ::
  ::  Returns the LOOBEAN comparison of two floating-point rays, any close to
  ::    Examples
  ::      > (any-close:sa:sa (ones:la:la [~[5 1] 5 %i754 ~]) (en-ray:la:la [~[5 1] 5 %i754 ~] ~[.1 .0 .1 .2 .0]))
  ::      %.y
  ::      > (any-close:sa:sa (ones:la:la [~[5 1] 5 %i754 ~]) (en-ray:la:la [~[5 1] 5 %i754 ~] ~[.1 .0 .1 .2 .0]))
  ::      %.y
  ::  Source
  ++  any-close  any:(lake rnd)
  ::
  ::  Algebraic
  ::
  ::    +add:  [$ray $ray] -> $ray
  ::
  ::  Returns the sum of two floating-point rays
  ::  Source
  ++  add  add:(lake rnd)
  ::    +sub:  [$ray $ray] -> $ray
  ::
  ::  Returns the difference of two floating-point rays
  ::  Source
  ++  sub  sub:(lake rnd)
  ::    +mul:  [$ray $ray] -> $ray
  ::
  ::  Returns the product of two floating-point rays
  ::  Source
  ++  mul  mul:(lake rnd)
  ::    +div:  [$ray $ray] -> $ray
  ::
  ::  Returns the quotient of two floating-point rays
  ::  Source
  ++  div  div:(lake rnd)
  ::    +eml:  [$ray $ray] -> $ray
  ::
  ::  Returns exp(x) - ln(y) elementwise across two floating-point rays.
  ::  Source
  ++  eml
    ~/  %eml
    |=  [a=ray:ls b=ray:ls]
    ^-  ray
    (bin-op:la a b (fun-scalar meta.a %eml))
  ::    +fma:  [$ray $ray $ray] -> $ray
  ::
  ::  Returns the fused multiply-add of three floating-point rays
  ::  Examples
  ::    > (fma:sa:sa:sa (ones:la:la [~[5 1] 5 %i754 ~]) (ones:la:la [~[5 1] 5 %i754 ~]) (ones:la:la [~[5 1] 5 %i754 ~]))
  ::    [meta=[shape=~[5 1] bloq=5 kind=%i754 fxp=~] data=0x1.4000.0000.4000.0000.4000.0000.4000.0000.4000.0000]
  ::  Source
  ++  fma  |=([a=ray:ls b=ray:ls c=ray:ls] (add:(lake rnd) (mul:(lake rnd) a b) c))
  ::    +neg:  $ray -> $ray
  ::
  ::  Returns the negation of each entry in a floating-point ray
  ::  Source
  ++  neg
    |=  a=ray:ls
    ^-  ray
    (el-wise-op:la a (trans-scalar bloq.meta.a kind.meta.a %neg))
  ::    +factorial:  $ray -> $ray
  ::
  ::  Returns the factorial of each entry in a floating-point ray
  ::  Source
  ++  factorial
    |=  a=ray:ls
    ^-  ray
    (el-wise-op:la a (trans-scalar bloq.meta.a kind.meta.a %factorial))
  ::    +abs: $ray -> $ray
  ::
  ::  Returns the absolute value of each entry in a floating-point ray
  ::  Source
  ++  abs  abs:(lake rnd)
  ::    +exp: $ray -> $ray
  ::
  ::  Returns the exponential of each entry in a floating-point ray
  ::  Source
  ++  exp
    |=  a=ray:ls
    ^-  ray
    (el-wise-op:la a (trans-scalar bloq.meta.a kind.meta.a %exp))
  ::    +sin: $ray -> $ray
  ::
  ::  Returns the sine of each entry in a floating-point ray
  ::  Source
  ++  sin
    |=  a=ray:ls
    ^-  ray
    (el-wise-op:la a (trans-scalar bloq.meta.a kind.meta.a %sin))
  ::    +cos: $ray -> $ray
  ::
  ::  Returns the cosine of each entry in a floating-point ray
  ::  Source
  ++  cos
    |=  a=ray:ls
    ^-  ray
    (el-wise-op:la a (trans-scalar bloq.meta.a kind.meta.a %cos))
  ::    +tan: $ray -> $ray
  ::
  ::  Returns the tangent of each entry in a floating-point ray
  ::  Source
  ++  tan
    |=  a=ray:ls
    ^-  ray
    (el-wise-op:la a (trans-scalar bloq.meta.a kind.meta.a %tan))
  ::    +pow-n: [$ray $ray] -> $ray
  ::
  ::  Returns the exponentiation of each entry in a floating-point ray by another ray
  ::  Source
  ++  pow-n
    |=  [a=ray:ls b=ray:ls]
    ^-  ray
    (bin-op:la a b (fun-scalar meta.a %pow-n))
  ::    +log: $ray -> $ray
  ::
  ::  Returns the natural logarithm of each entry in a floating-point ray
  ::  Source
  ++  log
    |=  a=ray:ls
    ^-  ray
    (el-wise-op:la a (trans-scalar bloq.meta.a kind.meta.a %log))
  ::    +log-10: $ray -> $ray
  ::
  ::  Returns the base-10 logarithm of each entry in a floating-point ray
  ::  Source
  ++  log-10
    |=  a=ray:ls
    ^-  ray
    (el-wise-op:la a (trans-scalar bloq.meta.a kind.meta.a %log-10))
  ::    +log-2: $ray -> $ray
  ::
  ::  Returns the base-2 logarithm of each entry in a floating-point ray
  ::  Source
  ++  log-2
    |=  a=ray:ls
    ^-  ray
    (el-wise-op:la a (trans-scalar bloq.meta.a kind.meta.a %log-2))
  ::    +pow: [$ray $ray] -> $ray
  ::
  ::  Returns the exponentiation of each entry in a floating-point ray by another ray
  ::  Source
  ++  pow
    |=  [a=ray:ls b=ray:ls]
    ^-  ray
    (bin-op:la a b (fun-scalar meta.a %pow))
  ::    +sqrt: $ray -> $ray
  ::
  ::  Returns the square root of each entry in a floating-point ray
  ::  Source
  ++  sqrt
    |=  a=ray:ls
    ^-  ray
    (el-wise-op:la a (trans-scalar bloq.meta.a kind.meta.a %sqrt))
  ::    +sqt: $ray -> $ray
  ::
  ::  Returns the square root of each entry in a floating-point ray
  ::  Alias for +sqrt.
  ::  Source
  ++  sqt  sqrt
  ::    +cbrt: $ray -> $ray
  ::
  ::  Returns the cube root of each entry in a floating-point ray
  ::  Source
  ++  cbrt
    |=  a=ray:ls
    ^-  ray
    (el-wise-op:la a (trans-scalar bloq.meta.a kind.meta.a %cbrt))
  ::    +cbt: $ray -> $ray
  ::
  ::  Returns the cube root of each entry in a floating-point ray
  ::  Alias for +cbrt.
  ::  Source
  ++  cbt  cbrt
  ::
  ::  Transformer activation functions
  ::  Composed from ray primitives; each has a ~/hint for future jetting.
  ::
  ::    +relu: $ray -> $ray
  ::
  ::  Returns max(0, x) elementwise.
  ::  Source
  ++  relu
    ~/  %relu
    |=  a=ray:ls
    ^-  ray
    =,  (lake rnd)
    =/  z  (zeros:la meta.a)
    =/  mask  (gth a z)
    (mul a mask)
  ::    +sigmoid: $ray -> $ray
  ::
  ::  Returns 1 / (1 + exp(-x)) elementwise.
  ::  Source
  ++  sigmoid
    ~/  %sigmoid
    |=  a=ray:ls
    ^-  ray
    =,  (lake rnd)
    =/  one  (ones:la meta.a)
    (div one (add one (exp (neg a))))
  ::    +tanh: $ray -> $ray
  ::
  ::  Returns hyperbolic tangent: (exp(2x) - 1) / (exp(2x) + 1).
  ::  Source
  ++  tanh
    ~/  %tanh
    |=  a=ray:ls
    ^-  ray
    =,  (lake rnd)
    ::  stable form: tanh(x) = 1 - 2/(1 + e^(2x))
    ::  when e^(2x) overflows to +inf, 2/(1+inf)=0, result=1 (correct).
    ::  the naive (e^2x - 1)/(e^2x + 1) gives NaN for overflow.
    =/  one  (ones:la meta.a)
    =/  two  (add one one)
    =/  e2x  (exp (add a a))
    (sub one (div two (add one e2x)))
  ::    +gelu: $ray -> $ray
  ::
  ::  GELU activation: 0.5 * x * (1 + tanh(sqrt(2/pi) * (x + 0.044715 * x^3)))
  ::  Source
  ++  gelu
    ~/  %gelu
    |=  a=ray:ls
    ^-  ray
    =,  (lake rnd)
    =/  one  (ones:la meta.a)
    =/  x3  (mul (mul a a) a)
    =/  inner  (add a (mul-scalar:la x3 (fcon bloq.meta.a kind.meta.a %gelu-coef)))
    =/  th  (tanh (mul-scalar:la inner (fcon bloq.meta.a kind.meta.a %sqrt2pi)))
    (mul-scalar:la (mul a (add one th)) (fcon bloq.meta.a kind.meta.a %half))
  ::    +softmax: $ray -> $ray
  ::
  ::  Softmax over flat ray: exp(x - max(x)) / sum(exp(x - max(x)))
  ::  Numerically stable via max subtraction.
  ::  Source
  ++  softmax
    ~/  %softmax
    |=  a=ray:ls
    ^-  ray
    =,  (lake rnd)
    ::  subtract max for numerical stability
    =/  mx  (max a)
    =/  mx-idx  (reap (lent shape.meta.mx) 0)
    =/  shifted  (sub-scalar a (get-item mx mx-idx))
    =/  exps  (exp shifted)
    =/  sm  (cumsum exps)
    =/  sm-idx  (reap (lent shape.meta.sm) 0)
    (div-scalar exps (get-item sm sm-idx))
  ::    +layer-norm: [$ray $ray $ray] -> $ray
  ::
  ::  Layer normalization: gamma * (x - mean) / sqrt(var + eps) + beta
  ::  gamma and beta are learnable parameter rays matching input shape.
  ::  Source
  ++  layer-norm
    ~/  %layer-norm
    |=  [x=ray:ls gamma=ray:ls beta=ray:ls]
    ^-  ray
    =/  n-elements  (roll shape.meta.x ^mul)
    =,  (lake rnd)
    =/  zero-idx  (reap (lent shape.meta.x) 0)
    =/  n-val  (fsun bloq.meta.x kind.meta.x n-elements)
    ::  mean = sum(x) / n
    =/  mean-val
      =/  sum-raw  (get-item:la (cumsum:la x) zero-idx)
      (fdiv bloq.meta.x kind.meta.x sum-raw n-val)
    =/  mu  (fill:la meta.x mean-val)
    =/  diff  (sub x mu)
    ::  var = sum((x - mean)^2) / n
    =/  var-val
      =/  sq-sum  (get-item:la (cumsum:la (mul diff diff)) zero-idx)
      (fdiv bloq.meta.x kind.meta.x sq-sum n-val)
    =/  eps-val  (fcon bloq.meta.x kind.meta.x %eps)
    =/  std  (sqrt (add-scalar:la (fill:la meta.x var-val) eps-val))
    ::  gamma * (x - mean) / std + beta
    (add (mul gamma (div diff std)) beta)
  ::
  ::    +rms-norm: [$ray $ray @rs] -> $ray
  ::
  ::  RMS normalization: gamma * x / sqrt(mean(x²) + eps)
  ::  No mean subtraction, no beta. Used by Llama/Qwen-family models.
  ::  Source
  ++  rms-norm
    ~/  %rms-norm
    |=  [x=ray:ls gamma=ray:ls eps=@rs]
    ^-  ray
    =/  n-elements  (roll shape.meta.x ^mul)
    =,  (lake rnd)
    =/  zero-idx  (reap (lent shape.meta.x) 0)
    =/  n-val  (fsun bloq.meta.x kind.meta.x n-elements)
    ::  ms = sum(x²) / n
    =/  ms-val
      =/  sq-sum  (get-item:la (cumsum:la (mul x x)) zero-idx)
      (fdiv bloq.meta.x kind.meta.x sq-sum n-val)
    =/  rms  (sqrt (add-scalar:la (fill:la meta.x ms-val) eps))
    ::  gamma * (x / rms)
    (mul gamma (div x rms))
  ::
  ::    +silu: $ray -> $ray
  ::
  ::  SiLU (swish) activation: x * sigmoid(x) = x / (1 + exp(-x)).
  ::  Used by Llama/Qwen SwiGLU MLPs.
  ::  Source
  ++  silu
    ~/  %silu
    |=  x=ray:ls
    ^-  ray
    =,  (lake rnd)
    ::  sigmoid(x) = 1 / (1 + exp(-x))
    =/  one       (fcon bloq.meta.x kind.meta.x %one)
    =/  neg-x     (mul-scalar:la x (fcon bloq.meta.x kind.meta.x %neg-one))
    =/  exp-nx    (exp neg-x)
    =/  denom     (add-scalar:la exp-nx one)
    (mul x (div (fill:la meta.x one) denom))
  ::
  ::  Precision-aware float constants and scalar ops
  ::
  ++  fcon
    |=  [=bloq =kind con=@tas]
    ^-  @
    ?>  =(%i754 kind)
    ?+    con  !!
        %half
      ?+(bloq !! %7 .~~~0.5, %6 .~0.5, %5 .0.5, %4 .~~0.5)
        %gelu-coef
      ?+(bloq !! %7 .~~~0.044715, %6 .~0.044715, %5 .0.044715, %4 .~~0.04474)
        %sqrt2pi
      ?+(bloq !! %7 .~~~0.7978845608028654, %6 .~0.7978845608028654, %5 .0.79788456, %4 .~~0.7979)
        %eps
      ?+(bloq !! %7 .~~~1e-5, %6 .~1e-5, %5 .1e-5, %4 .~~0.001)
        %neg-inf
      ?+(bloq !! %7 `@rq`0xffff.0000.0000.0000.0000.0000.0000.0000, %6 `@rd`0xfff0.0000.0000.0000, %5 `@rs`0xff80.0000, %4 `@rh`0xfc00)
        %one
      ?+(bloq !! %7 .~~~1, %6 .~1, %5 .1, %4 .~~1)
        %neg-one
      ?+(bloq !! %7 .~~~-1, %6 .~-1, %5 .-1, %4 .~~-1)
    ==
  ++  fsun
    |=  [=bloq =kind n=@ud]
    ^-  @
    ?>  =(%i754 kind)
    ?+(bloq !! %7 (~(sun rq rnd) n), %6 (~(sun rd rnd) n), %5 (~(sun rs rnd) n), %4 (~(sun rh rnd) n))
  ++  fdiv
    |=  [=bloq =kind a=@ b=@]
    ^-  @
    ?>  =(%i754 kind)
    ?+(bloq !! %7 (~(div rq rnd) a b), %6 (~(div rd rnd) a b), %5 (~(div rs rnd) a b), %4 (~(div rh rnd) a b))
  ::
  +$  unary-ops   $?  %neg
                      %factorial
                      %exp
                      %sin
                      %cos
                      %tan
                      %log
                      %log-10
                      %log-2
                      %sqrt
                      %cbrt
                  ==
  ::
  ++  trans-scalar
    |=  [=bloq =kind fun=unary-ops]
    ^-  $-(@ @)
    ?-    kind
        %int2  !!
        %uint
      ?-  fun
        %neg        !!
        %factorial  |=(x=@u ^-(@u =/(t 1 ?:(=(0 x) t ?:(=(1 x) t |-(?:(=(1 x) t $(x (^sub x 1), t (^mul t x)))))))))
        %exp        !!
        %sin        !!
        %cos        !!
        %tan        !!
        %log        !!
        %log-10     !!
        %log-2      !!
        %sqrt       !!
        %cbrt       !!
      ==  ::  fun
      ::
        %i754
      ?+    bloq  !!
          %7
        ?-  fun
          %neg        ~(neg rq:math [rnd rtol])
          %factorial  ~(factorial rq:math [rnd rtol])
          %exp        ~(exp rq:math [rnd rtol])
          %sin        ~(sin rq:math [rnd rtol])
          %cos        ~(cos rq:math [rnd rtol])
          %tan        ~(tan rq:math [rnd rtol])
          %log        ~(log rq:math [rnd rtol])
          %log-10     ~(log-10 rq:math [rnd rtol])
          %log-2      ~(log-2 rq:math [rnd rtol])
          %sqrt       ~(sqrt rq:math [rnd rtol])
          %cbrt       ~(cbrt rq:math [rnd rtol])
        ==  ::  fun
          %6
        ?-  fun
          %neg        ~(neg rd:math [rnd rtol])
          %factorial  ~(factorial rd:math [rnd rtol])
          %exp        ~(exp rd:math [rnd rtol])
          %sin        ~(sin rd:math [rnd rtol])
          %cos        ~(cos rd:math [rnd rtol])
          %tan        ~(tan rd:math [rnd rtol])
          %log        ~(log rd:math [rnd rtol])
          %log-10     ~(log-10 rd:math [rnd rtol])
          %log-2      ~(log-2 rd:math [rnd rtol])
          %sqrt       ~(sqrt rd:math [rnd rtol])
          %cbrt       ~(cbrt rd:math [rnd rtol])
        ==  ::  fun
          %5
        ?-  fun
          %neg        ~(neg rs:math [rnd rtol])
          %factorial  ~(factorial rs:math [rnd rtol])
          %exp        ~(exp rs:math [rnd rtol])
          %sin        ~(sin rs:math [rnd rtol])
          %cos        ~(cos rs:math [rnd rtol])
          %tan        ~(tan rs:math [rnd rtol])
          %log        ~(log rs:math [rnd rtol])
          %log-10     ~(log-10 rs:math [rnd rtol])
          %log-2      ~(log-2 rs:math [rnd rtol])
          %sqrt       ~(sqrt rs:math [rnd rtol])
          %cbrt       ~(cbrt rs:math [rnd rtol])
        ==  ::  fun
          %4
        ?-  fun
          %neg        ~(neg rh:math [rnd rtol])
          %factorial  ~(factorial rh:math [rnd rtol])
          %exp        ~(exp rh:math [rnd rtol])
          %sin        ~(sin rh:math [rnd rtol])
          %cos        ~(cos rh:math [rnd rtol])
          %tan        ~(tan rh:math [rnd rtol])
          %log        ~(log rh:math [rnd rtol])
          %log-10     ~(log-10 rh:math [rnd rtol])
          %log-2      ~(log-2 rh:math [rnd rtol])
          %sqrt       ~(sqrt rh:math [rnd rtol])
          %cbrt       ~(cbrt rh:math [rnd rtol])
        ==  ::  fun
      ==  ::  bloq
    ==  ::  kind
  ::
  +$  binary-ops  $?  %eml
                      %pow-n
                      %pow
                  ==
  ::
  ++  fun-scalar
    |=  [=meta fun=binary-ops]
    ^-  $-([@ @] @)
    ?-    kind.meta
        %int2  !!
        %uint
      ?-  fun
        %eml        !!
        %pow        (fun-scalar meta %pow-n)
        %pow-n      |=([x=@u n=@u] ^-(@u ?:(=(0 n) 1 =/(p x |-(?:((^lth n 2) p $(n (dec n), p (^mul p x))))))))
      ==  ::  fun
      ::
        %i754
      ?+    bloq.meta  !!
          %7
        ?-  fun
          %eml        ~(eml rq:math [rnd rtol])
          %pow-n      ~(pow-n rq:math [rnd rtol])
          %pow        ~(pow rq:math [rnd rtol])
        ==  ::  fun
          %6
        ?-  fun
          %eml        ~(eml rd:math [rnd rtol])
          %pow-n      ~(pow-n rd:math [rnd rtol])
          %pow        ~(pow rd:math [rnd rtol])
        ==  ::  fun
          %5
        ?-  fun
          %eml        ~(eml rs:math [rnd rtol])
          %pow-n      ~(pow-n rs:math [rnd rtol])
          %pow        ~(pow rs:math [rnd rtol])
        ==  ::  fun
          %4
        ?-  fun
          %eml        ~(eml rh:math [rnd rtol])
          %pow-n      ~(pow-n rh:math [rnd rtol])
          %pow        ~(pow rh:math [rnd rtol])
        ==  ::  fun
      ==  ::  bloq
    ==  ::  kind
  --
--
