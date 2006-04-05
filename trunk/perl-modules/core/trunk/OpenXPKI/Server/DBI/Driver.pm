## OpenXPKI::Server::DBI::Driver
##
## Written by Michael Bell for the OpenXPKI::Server project 2005
## Copyright (C) 2005 by The OpenXPKI Project
## $Revision$

use strict;
use warnings;
use utf8;

package OpenXPKI::Server::DBI::Driver;

use vars qw(@ISA);
use OpenXPKI::Exception;

use OpenXPKI::Server::DBI::Schema;
use OpenXPKI::Server::DBI::Driver::DB2;
use OpenXPKI::Server::DBI::Driver::MySQL;
## use OpenXPKI::Server::DBI::Driver::Oracle;
use OpenXPKI::Server::DBI::Driver::PostgreSQL;
use OpenXPKI::Server::DBI::Driver::SQLite;

=head1 SQL assumptions

The most important and difficult stuff is the serial handling of X.509.
The length of these serials was defined in RFC 3280 4.1.2.2.
Such serials can have the size of a 20 byte integer. This is larger than
the most supported integer types. It is an integer called 256^20. We
have to perform a small aproximation for the decimal length:

256^10 = 256^2)^10
       = 65535^10
       = (65535^2)^5
       = 4294836225^5
       < 4300000000^5 = (43*10^8)^5
                      = 43^5*10^40
                      = 147.008.443*10^40
                      < 10^9*10^40 = 10^49

Some systems support such large decimal numbers. Other systems have a
problem with this. Otherwise we need a working ordering at minimum for
requests. This does not work if we use C<varchar>.

The idea is a small hack. We use BIGINT for real integers and NUMERIC
for virtual integers. This means that BIGINT must be mapped to an
integer datatype while NUMERIC can be mapped to a character datatype
too. If there is a field which is an integer but it must support large
certificate serials then we use NUMERIC. Otherwise we use BIGINT.

=head1 Variables

The only global variable is COLUMN which includes a mapping
from SQL columns to abstract types. The module replaces the
abstract types by the real types of the driver during the
execution of the constructor function new.

=cut

our %COLUMN = (
    "submit_date"      => "TEXT",
    "format"           => "TEXT",
    "data"             => "LONGTEXT",

    "pki_realm"        => "TEXT_KEY",
    "ca_name"          => "TEXT_KEY",
    "issuing_ca"       => "TEXT_KEY",
    "issuing_pki_realm"=> "TEXT_KEY",

    "cert_key"         => "NUMERIC",
    "req_key"          => "BIGINT",
    "crr_key"          => "BIGINT",
    "crl_key"          => "NUMERIC",
    "audittrail_key"   => "SERIAL",
    "global_id"        => "BIGINT",
    "data_key"         => "BIGINT",
    "private_key"      => "BIGINT",
    "signature_key"    => "BIGINT",
    "global_id"        => "BIGINT",
    "dataexchange_key" => "BIGINT",

    "subject"          => "TEXT_KEY",
    "email"            => "TEXT",
    "ra"               => "TEXT",
    "last_update"      => "BIGINT",
    "next_update"      => "BIGINT",
    "role"             => "TEXT",
    "public_key"       => "TEXT",
    "notafter"         => "BIGINT",
    "notbefore"        => "BIGINT",
    "scep_tid"         => "TEXT",
    "loa"              => "TEXT",
    "public_cert"      => "BIGINT",
    
    "status"           => "TEXT",
    "reason"           => "TEXT",
    "object_serial"    => "NUMERIC",
    "object_type"      => "TEXT_KEY",
    "object_status"    => "TEXT_KEY",
    "valid_until"      => "TEXT",
    "server_id"        => "BIGINT",
    "export_id"        => "BIGINT",

    "column_name"      => "TEXT_KEY",
    "array_counter"    => "BIGINT",
    "content_type"     => "TEXT",
    "int_content"      => "NUMERIC",
    "char_content"     => "TEXT",

    "logtimestamp"     => "TIMESTAMP",
    "message"          => "TEXT",
    "category"         => "TEXT_KEY",
    "level"            => "TEXT_KEY",

    "keyid"            => "TEXT_KEY",
    "ca_issuer_name"   => "TEXT_KEY",
    "ca_issuer_serial" => "NUMERIC",
    
    "workflow_hist_id" => "BIGINT",
    "workflow_id"      => "BIGINT",
    "workflow_type"    => "TEXT_KEY",
    "workflow_state"   => "TEXT_KEY",
    "workflow_last_update" => "TIMESTAMP",
    "workflow_action"  => "TEXT_KEY",
    "workflow_description" => "TEXT_KEY",
    "workflow_user"    => "TEXT_KEY",
    "workflow_history_date"  => "TIMESTAMP",
    "workflow_context_key"   => "TEXT_KEY",
    "workflow_context_value"   => "TEXT",
    
    );

=head1 Functions

=head2 new

The constructor expects at minimum three parameters - DBH with an
instance of OpenXPKI::Server::DBI::DBH and DB_Type with the driver name.
All other parameters are
exclusively to initialize the driver instance. Please check
the specification of the driver function get_dsn for the
additionally supported parameters.

=cut

sub new
{
    my $self   = {};
    my $class  = shift;
    bless $self, $class;

    $self->{schema} = OpenXPKI::Server::DBI::Schema->new();

    $self->{params} = { @_ };
    my $driver = "OpenXPKI::Server::DBI::Driver::".$self->{params}->{TYPE};

    @ISA = ($driver);

    ## init SQL types for the columns
    my %type = eval ("\%${driver}::TYPE");
    foreach my $key (keys %COLUMN)
    {
        if (not exists $type{$COLUMN{$key}})
        {
            OpenXPKI::Exception->throw (
                message => "I18N_OPENXPKI_SERVER_DBI_DRIVER_NEW_WRONG_TYPE_IN_SCHEMA",
                params  => {"COLUMN" => $key, "TYPE" => $COLUMN{$key}});
        }
        $self->{column}->{$key} = $type{$COLUMN{$key}};
    }

    ## DBI_OPTION and LIMIT must be set by the driver
    $self->{dbi_option}   = eval ("\$${driver}::DBI_OPTION");
    $self->{limit}        = eval ("\$${driver}::LIMIT");
    my $option = eval ("\$${driver}::TABLE_OPTION");
    $self->{table_option} = $option if ($option);

    return $self;
}

=head2 column_is_numeric

returns true if a column is numeric

=cut

sub column_is_numeric
{
    my $self = shift;
    my $key  = shift;
    ## FIXME: SQL types are standardized but actually we check only for numeric
    return 1 if ($self->{column}->{$key} =~ /NUMERIC/i);
    return 0;
}

=head2 column_is_string

returns true if a column is a string

=cut

sub column_is_string
{
    my $self = shift;
    my $key  = shift;
    ## FIXME: SQL types are standardized but actually we check only for numeric
    return 1 if ($self->{column}->{$key} !~ /NUMERIC/i);
    return 0;
}

=head2 get_table_option

returns a string with options which can be attached to the SQL
command which creates a table.

=cut

sub get_table_option
{
    my $self = shift;
    return "" if (not exists $self->{table_option});
    return $self->{table_option};
}

=head2 get_column_type

returns the native SQL type of a specific database for the specified column.

=cut

sub get_column_type
{
    my $self = shift;
    my $col  = shift;

    if (not exists $self->{column}->{$col})
    {
        OpenXPKI::Exception->throw (
            message => "I18N_OPENXPKI_SERVER_DBI_DRIVER_GET_COLUMN_TYPE_UNKNOWN_NAME",
            params  => {"COLUMN" => $col});
    }

    return $self->{column}->{$col};
}

=head2 get_abstract_column_type

returns the original column type which is not database specific. This is
useful if you want to detect how you have to handle a special column. Pleasde see
the description of the driver requirements for more details about datatypes.

=cut

sub get_abstract_column_type
{
    my $self = shift;
    my $col  = shift;

    if (not exists $COLUMN{$col})
    {
        OpenXPKI::Exception->throw (
            message => "I18N_OPENXPKI_SERVER_DBI_DRIVER_GET_ABSTRACT_COLUMN_TYPE_UNKNOWN_NAME",
            params  => {"COLUMN" => $col});
    }

    return $COLUMN{$col};
}

=head1 Driver Specification

=head2 Variables

=head3 TYPE

This variable must be supported by the driver.

This is a hash which must include the real SQL types of the following
abstract types:

=over 4

=item * TEXT

=item * TIMESTAMP

=item * LONGTEXT (the only type which may not be searchable via a where clause)

=item * TEXT_KEY

=item * BIGINT

=item * NUMERIC

=item * SERIAL

This must be a complete specification of an integer which
increments itself - e.g. auto_increment or serial. Please
see the other drivers for some examples. This is really critical
for logging.

=back

=head3 DBI_OPTION

This variable must be supported by the driver.

It contains the hash reference with the DBI options
for the database connection.

=head3 LIMIT

This variable must be supported by the driver.

This variable contains a string with the substrings __QUERY__ and
__MAXITEMS__. These substrings will be substituted by the corresponding
values. After this the resulting query will be executed and should only
return __MAXITEMS__ results of the original __QUERY__.

=head3 TABLE_OPTION

This variable can be supported by the driver.

This string will be attached to SQL code which creates a new table.
It can be used for example to specify a storage type
(e.g. MySQL: "Type=InnoDB").

=head2 Functions

All specified functions must be supported by each driver.

=head3 get_dsn

must return the DSN which can be used by DBI to connect to the database.
The parameters which will be passed are the following:

=over 4

=item * NAME

=back

The drivers may use only a subset of the parameters.

=head3 get_new_serial

returns a new serial for the specified table. The table can be
specified with the parameter TABLE.

=head3 sequence_exists

checks whether a sequence which is specified with NAME exists or not.

=head3 create_sequence

create a sequence which is specified with NAME. If the parameter MODE
is set to dryrun then the function returns the executed SQL code and
does not execute the code directly. This is used to allow users
to execute such critical code by themselves.

=head1 See also

OpenXPKI::Server::DBI::DBH, OpenXPKI::Server::DBI::Schema and OpenXPKI::Server::DBI::SQLite

=cut

1;
