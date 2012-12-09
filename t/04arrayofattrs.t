use strict;
use warnings;
use Test::More;

{
	package Local::Role;
	use Moo::Role;
	use MooX::late;
	has [qw(foo1 foo2)] => (is => 'ro', isa => 'Str', lazy_build => 1);
	sub _build_foo1 { 'foo1' };
	sub _build_foo2 { 'foo2' };
}

{
	package Local::Class;
	use Moo;
	use MooX::late;
	with 'Local::Role';
	has [qw(bar1 bar2)] => (is => 'ro', isa => 'Str', lazy_build => 1);
	sub _build_bar1 { 'bar1' };
	sub _build_bar2 { 'bar2' };
}

my $o1 = Local::Class->new;
is($o1->foo1, 'foo1');
is($o1->foo2, 'foo2');
is($o1->bar1, 'bar1');
is($o1->bar2, 'bar2');

done_testing;
