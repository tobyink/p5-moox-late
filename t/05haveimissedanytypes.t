
use strict;
use warnings;
use Test::More;

require Moo;

my @types_to_check = qw(
	Any
	Item
	Bool
	Maybe
	Maybe[Int]
	Undef
	Defined
	Value
	Str
	Num
	Int
	ClassName
	RoleName
	Ref
	ScalarRef
	ScalarRef[Int]
	ArrayRef
	ArrayRef[Int]
	HashRef
	HashRef[Int]
	CodeRef
	RegexpRef
	GlobRef
	FileHandle
	Object
);

my @class_types_to_check = qw(
	Local::Test1
	Local::Test::Two
	LocalTest3
);

my $count = 0;
sub constraint_for
{
	my $type  = shift;
	my $class = "Local::Test" . ++$count;
	
	eval qq{
		package $class;
		use Moo;
		use MooX::late;
		has attr => (is => "ro", isa => "$type");
		1;
	} or die $@;
	
	"Moo"->_constructor_maker_for($class)->all_attribute_specs->{attr}{isa};
}

for my $type (@types_to_check)
{
	my $got = constraint_for($type);	
	isa_ok($got, "Type::Tiny", "constraint_for('$type')");
	is("$got", "$type", "Type constraint returned for '$type' looks right.");
}

for my $type (@class_types_to_check)
{
	my $got = constraint_for($type);	
	isa_ok($got, "Type::Tiny::Class", "constraint_for('$type')");
	is($got->class, $type, "Type constraint returned for '$type' looks right.");
}

done_testing;
