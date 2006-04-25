
use strict;
use warnings;
use Test::More tests => 8;
use English;

BEGIN { use_ok( 'OpenXPKI::Serialization::Simple' ); }

print STDERR "OpenXPKI::Serialization::Simple\n";

# test illegal separators
eval
{
    OpenXPKI::Serialization::Simple->new
    ({
        SEPARATOR => "ab"
    });
};
ok($EVAL_ERROR);
eval
{
    OpenXPKI::Serialization::Simple->new
    ({
        SEPARATOR => "1"
    });
};
ok($EVAL_ERROR);

# test default separator
my $ref = OpenXPKI::Serialization::Simple->new ();
ok($ref);

# using "-" to make testing easier
$ref = OpenXPKI::Serialization::Simple->new
             ({
                 SEPARATOR => "-"
             });
ok($ref);

my $hash = {
            "HEADER" => ["Testheader"],
            "LIST"   => [
                         {"Name"   => ["John Doe"],
                          "Serial" => [10, 12]
                         },
                         {"Name"   => ["Jane Doe"],
                          "Serial" => [11, 13]
                         }
                        ],
            "FOOTER" => ["OK", "Abort"]
           };
my $text = $ref->serialize ($hash);
my $expected_serialization = "HASH-291-6-FOOTER-ARRAY-31-0-SCALAR-2-OK-1-SCALAR-5-Abort-4-LIST-ARRAY-184-0-HASH-82-6-Serial-ARRAY-28-0-SCALAR-2-10-1-SCALAR-2-12-4-Name-ARRAY-20-0-SCALAR-8-John Doe-1-HASH-82-6-Serial-ARRAY-28-0-SCALAR-2-11-1-SCALAR-2-13-4-Name-ARRAY-20-0-SCALAR-8-Jane Doe-6-HEADER-ARRAY-23-0-SCALAR-10-Testheader-";
ok($text eq $expected_serialization);

my $res = $ref->deserialize($text);
ok($res);

is_deeply($res, $hash, "Data structure survived (de)serialization");

1;
