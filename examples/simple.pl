package Foo;
use Moo;
use MooX::late;
has bar => (is => 'ro', isa => 'Str|ArrayRef[Int|Num]|Int');

Foo->new(bar => [1, "xyz", 3])
