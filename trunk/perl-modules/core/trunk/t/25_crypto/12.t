use strict;
use warnings;
use Test;
BEGIN { plan tests => 15 };

print STDERR "OpenXPKI::Crypto::Command: Conversion tests\n";

use OpenXPKI::Crypto::TokenManager;
use OpenXPKI qw (read_file);

our $cache;
our $basedir;
eval `cat t/25_crypto/common.pl`;

ok(1);

## parameter checks for TokenManager init

my $mgmt = OpenXPKI::Crypto::TokenManager->new (DEBUG => 0, CONFIG => $cache);
ok (1);

## parameter checks for get_token

my $token = $mgmt->get_token (TYPE => "CA", NAME => "INTERNAL_CA_1", PKI_REALM => "Test Root CA");
ok (1);

## load data
my $passwd = OpenXPKI->read_file ("$basedir/ca1/passwd.txt");
my $dsa    = OpenXPKI->read_file ("$basedir/ca1/dsa.pem");
my $rsa    = OpenXPKI->read_file ("$basedir/ca1/rsa.pem");
my $csr    = OpenXPKI->read_file ("$basedir/ca1/pkcs10.pem");
my $cert   = OpenXPKI->read_file ("$basedir/ca1/cert.pem");
my $crl    = OpenXPKI->read_file ("$basedir/ca1/crl.pem");
ok($passwd and $dsa and $rsa and $csr and $cert and $crl);

## DSA KEY: PEM --> DER
$token->command ({COMMAND => "convert_key",
                  DATA    => $dsa,
                  IN      => "DSA",
                  OUT     => "DER",
                  PASSWD  => $passwd});
ok(1);

## RSA KEY: PEM --> DER
$token->command ({COMMAND => "convert_key",
                  DATA    => $rsa,
                  IN      => "RSA",
                  OUT     => "DER",
                  PASSWD  => $passwd});
ok(1);

## DSA KEY: PEM --> PKCS#8
$token->command ({COMMAND => "convert_key",
                  DATA    => $dsa,
                  IN      => "DSA",
                  OUT     => "PKCS8",
                  PASSWD  => $passwd});
ok(1);

## RSA KEY: PEM --> PKCS#8
my $pkcs8 = $token->command ({COMMAND => "convert_key",
                              DATA   => $rsa,
                              IN     => "RSA",
                              OUT    => "PKCS8",
                              PASSWD => $passwd});
ok(1);

## PKCS#8: PEM --> DER
$token->command ({COMMAND => "convert_key",
                  DATA    => $pkcs8,
                  IN      => "PKCS8",
                  OUT     => "DER",
                  PASSWD  => $passwd});
ok(1);

## PKCS10: PEM --> DER
$token->command ({COMMAND => "convert_pkcs10",
                  DATA    => $csr,
                  OUT => "DER"});
ok(1);

## PKCS10: PEM --> TXT
$token->command ({COMMAND => "convert_pkcs10",
                  DATA    => $csr,
                  OUT     => "TXT"});
ok(1);

## Cert: PEM --> DER
$token->command ({COMMAND => "convert_cert",
                  DATA    => $cert,
                  OUT     => "DER"});
ok(1);

## Cert: PEM --> TXT
$token->command ({COMMAND => "convert_cert",
                  DATA    => $cert,
                  OUT     => "TXT"});
ok(1);

## CRL: PEM --> DER
$token->command ({COMMAND => "convert_crl",
                  DATA    => $crl,
                  OUT     => "DER"});
ok(1);

## CRL: PEM --> TXT
$token->command ({COMMAND => "convert_crl",
                  DATA    => $crl,
                  OUT     => "TXT"});
ok(1);

1;
