use Test::More tests => 2;

{
	package CalculatorAPI;
	use MooseX::Interface;

	requires 'add';
	test_case { $_->add(8, 2) == 10 };

	requires 'subtract';
	test_case { $_->subtract(8, 2) == 6 };

	requires 'multiply';
	test_case { $_->multiply(8, 2) == 16 };

	requires 'divide';
	test_case { $_->divide(8, 2) == 4 };
}

{
	package Calculator;
	use Moose;
	with 'CalculatorAPI';
	sub add      { $_[1] + $_[2] }
	sub subtract { $_[1] - $_[2] }
	sub multiply { $_[1] * $_[2] }
	sub divide   { $_[1] / $_[2] }
}

{
	package BrokenCalculator;
	use Moose;
	with 'CalculatorAPI';
	sub add      { $_[1] - $_[2] }
	sub subtract { $_[1] + $_[2] }
	sub multiply { $_[1] * $_[2] }
	sub divide   { $_[1] / $_[2] }
}

ok(
	CalculatorAPI->meta->test_implementation(Calculator->new)
);

ok(
	not CalculatorAPI->meta->test_implementation(BrokenCalculator->new)
);

