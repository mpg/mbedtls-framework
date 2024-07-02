#!/usr/bin/env perl
#
# psa_sim_serialise.pl - Sample Perl script to show how many serialisation
#                        functions can be created by templated scripting.
#
# This is an example only, and is expected to be replaced by a Python script
# for production use. It is not hooked into the build: it needs to be run
# manually:
#
# perl psa_sim_serialise.pl h > psa_sim_serialise.h
# perl psa_sim_serialise.pl c > psa_sim_serialise.c
#
# Copyright The Mbed TLS Contributors
# SPDX-License-Identifier: Apache-2.0 OR GPL-2.0-or-later
#
use strict;

my $usage = "$0: usage: $0 c|h\n";
my $which = lc(shift) || die($usage);
die($usage) unless $which eq "c" || $which eq "h";

# Most types are serialised as a fixed-size (per type) octet string, with
# no type indication. This is acceptable as (a) this is for the test PSA crypto
# simulator only, not production, and (b) these functions are called by
# code that itself is written by script.
#
# We also want to keep serialised data reasonably compact as communication
# between client and server goes in messages of less than 200 bytes each.
#
# This script is able to create serialisation functions for plain old C data
# types (e.g. unsigned int), types typedef'd to those, and even structures
# that don't contain pointers.
#
# Structures that contain pointers will need to have their serialisation and
# deserialisation functions written manually (like those for the "buffer" type
# are).
#
my @types = qw(unsigned-int int size_t
               uint16_t uint32_t uint64_t
               buffer
               psa_key_production_parameters_t
               psa_status_t psa_algorithm_t psa_key_derivation_step_t
               psa_hash_operation_t
               psa_aead_operation_t
               psa_key_attributes_t
               psa_mac_operation_t
               psa_cipher_operation_t
               psa_key_derivation_operation_t
               psa_sign_hash_interruptible_operation_t
               psa_verify_hash_interruptible_operation_t
               mbedtls_svc_key_id_t);

grep(s/-/ /g, @types);

# IS-A: Some data types are typedef'd; we serialise them as the other type
my %isa = (
    "psa_status_t" => "int",
    "psa_algorithm_t" => "unsigned int",
    "psa_key_derivation_step_t" => "uint16_t",
);

if ($which eq "h") {

    print h_header();

    for my $type (@types) {
        if ($type eq "buffer") {
            print declare_buffer_functions();
        } elsif ($type eq "psa_key_production_parameters_t") {
            print declare_psa_key_production_parameters_t_functions();
        } else {
            print declare_needs($type, "");
            print declare_serialise($type, "");
            print declare_deserialise($type, "");

            if ($type =~ /^psa_\w+_operation_t$/) {
                print declare_needs($type, "server_");
                print declare_serialise($type, "server_");
                print declare_deserialise($type, "server_");
            }
        }
    }

} elsif ($which eq "c") {

    my $have_operation_types = (grep(/psa_\w+_operation_t/, @types)) ? 1 : 0;

    print c_header();
    print c_define_types_for_operation_types() if $have_operation_types;

    for my $type (@types) {
        next unless $type =~ /^psa_(\w+)_operation_t$/;
        print define_operation_type_data_and_functions($1);
    }

    print c_define_begins();

    for my $type (@types) {
        if ($type eq "buffer") {
            print define_buffer_functions();
        } elsif ($type eq "psa_key_production_parameters_t") {
            print define_psa_key_production_parameters_t_functions();
        } elsif (exists($isa{$type})) {
            print define_needs_isa($type, $isa{$type});
            print define_serialise_isa($type, $isa{$type});
            print define_deserialise_isa($type, $isa{$type});
        } else {
            print define_needs($type);
            print define_serialise($type);
            print define_deserialise($type);

            if ($type =~ /^psa_\w+_operation_t$/) {
                print define_server_needs($type);
                print define_server_serialise($type);
                print define_server_deserialise($type);
            }
        }
    }

    print define_server_serialize_reset(@types);
} else {
    die("internal error - shouldn't happen");
}

sub declare_needs
{
    my ($type, $server) = @_;

    my $an = ($type =~ /^[ui]/) ? "an" : "a";
    my $type_d = $type;
    $type_d =~ s/ /_/g;

    my $ptr = (length($server)) ? "*" : "";

    return <<EOF;

/** Return how much buffer space is needed by \\c psasim_${server}serialise_$type_d()
 *  to serialise $an `$type`.
 *
 * \\param value              The value that will be serialised into the buffer
 *                           (needed in case some serialisations are value-
 *                           dependent).
 *
 * \\return                   The number of bytes needed in the buffer by
 *                           \\c psasim_serialise_$type_d() to serialise
 *                           the given value.
 */
size_t psasim_${server}serialise_${type_d}_needs(
    $type ${ptr}value);
EOF
}

sub declare_serialise
{
    my ($type, $server) = @_;

    my $an = ($type =~ /^[ui]/) ? "an" : "a";
    my $type_d = $type;
    $type_d =~ s/ /_/g;

    my $server_side = (length($server)) ? " on the server side" : "";

    my $ptr = (length($server)) ? "*" : "";

    return align_declaration(<<EOF);

/** Serialise $an `$type` into a buffer${server_side}.
 *
 * \\param pos[in,out]        Pointer to a `uint8_t *` holding current position
 *                           in the buffer.
 * \\param remaining[in,out]  Pointer to a `size_t` holding number of bytes
 *                           remaining in the buffer.
 * \\param value              The value to serialise into the buffer.
 *
 * \\return                   \\c 1 on success ("okay"), \\c 0 on error.
 */
int psasim_${server}serialise_$type_d(uint8_t **pos,
                             size_t *remaining,
                             $type ${ptr}value);
EOF
}

sub declare_deserialise
{
    my ($type, $server) = @_;

    my $an = ($type =~ /^[ui]/) ? "an" : "a";
    my $type_d = $type;
    $type_d =~ s/ /_/g;

    my $server_side = (length($server)) ? " on the server side" : "";

    my $ptr = (length($server)) ? "*" : "";

    return align_declaration(<<EOF);

/** Deserialise $an `$type` from a buffer${server_side}.
 *
 * \\param pos[in,out]        Pointer to a `uint8_t *` holding current position
 *                           in the buffer.
 * \\param remaining[in,out]  Pointer to a `size_t` holding number of bytes
 *                           remaining in the buffer.
 * \\param value              Pointer to $an `$type` to receive the value
 *                           deserialised from the buffer.
 *
 * \\return                   \\c 1 on success ("okay"), \\c 0 on error.
 */
int psasim_${server}deserialise_$type_d(uint8_t **pos,
                               size_t *remaining,
                               $type ${ptr}*value);
EOF
}

sub declare_buffer_functions
{
    return <<'EOF';

/** Return how much space is needed by \c psasim_serialise_buffer()
 *  to serialise a buffer: a (`uint8_t *`, `size_t`) pair.
 *
 * \param buffer             Pointer to the buffer to be serialised
 *                           (needed in case some serialisations are value-
 *                           dependent).
 * \param buffer_size        Number of bytes in the buffer to be serialised.
 *
 * \return                   The number of bytes needed in the buffer by
 *                           \c psasim_serialise_buffer() to serialise
 *                           the specified buffer.
 */
size_t psasim_serialise_buffer_needs(const uint8_t *buffer, size_t buffer_size);

/** Serialise a buffer.
 *
 * \param pos[in,out]        Pointer to a `uint8_t *` holding current position
 *                           in the buffer.
 * \param remaining[in,out]  Pointer to a `size_t` holding number of bytes
 *                           remaining in the buffer.
 * \param buffer             Pointer to the buffer to be serialised.
 * \param buffer_length      Number of bytes in the buffer to be serialised.
 *
 * \return                   \c 1 on success ("okay"), \c 0 on error.
 */
int psasim_serialise_buffer(uint8_t **pos, size_t *remaining,
                            const uint8_t *buffer, size_t buffer_length);

/** Deserialise a buffer.
 *
 * \param pos[in,out]        Pointer to a `uint8_t *` holding current position
 *                           in the serialisation buffer.
 * \param remaining[in,out]  Pointer to a `size_t` holding number of bytes
 *                           remaining in the serialisation buffer.
 * \param buffer             Pointer to a `uint8_t *` to receive the address
 *                           of a newly-allocated buffer, which the caller
 *                           must `free()`.
 * \param buffer_length      Pointer to a `size_t` to receive the number of
 *                           bytes in the deserialised buffer.
 *
 * \return                   \c 1 on success ("okay"), \c 0 on error.
 */
int psasim_deserialise_buffer(uint8_t **pos, size_t *remaining,
                              uint8_t **buffer, size_t *buffer_length);

/** Deserialise a buffer returned from the server.
 *
 * When the client is deserialising a buffer returned from the server, it needs
 * to use this function to deserialised the  returned buffer. It should use the
 * usual \c psasim_serialise_buffer() function to serialise the outbound
 * buffer.
 *
 * \param pos[in,out]        Pointer to a `uint8_t *` holding current position
 *                           in the serialisation buffer.
 * \param remaining[in,out]  Pointer to a `size_t` holding number of bytes
 *                           remaining in the serialisation buffer.
 * \param buffer             Pointer to a `uint8_t *` to receive the address
 *                           of a newly-allocated buffer, which the caller
 *                           must `free()`.
 * \param buffer_length      Pointer to a `size_t` to receive the number of
 *                           bytes in the deserialised buffer.
 *
 * \return                   \c 1 on success ("okay"), \c 0 on error.
 */
int psasim_deserialise_return_buffer(uint8_t **pos, size_t *remaining,
                                     uint8_t *buffer, size_t buffer_length);
EOF
}

sub declare_psa_key_production_parameters_t_functions
{
    return <<'EOF';

/** Return how much space is needed by \c psasim_serialise_psa_key_production_parameters_t()
 *  to serialise a psa_key_production_parameters_t (a structure with a flexible array member).
 *
 * \param params             Pointer to the struct to be serialised
 *                           (needed in case some serialisations are value-
 *                           dependent).
 * \param data_length        Number of bytes in the data[] of the struct to be serialised.
 *
 * \return                   The number of bytes needed in the serialisation buffer by
 *                           \c psasim_serialise_psa_key_production_parameters_t() to serialise
 *                           the specified structure.
 */
size_t psasim_serialise_psa_key_production_parameters_t_needs(
    const psa_key_production_parameters_t *params,
    size_t buffer_size);

/** Serialise a psa_key_production_parameters_t.
 *
 * \param pos[in,out]        Pointer to a `uint8_t *` holding current position
 *                           in the buffer.
 * \param remaining[in,out]  Pointer to a `size_t` holding number of bytes
 *                           remaining in the buffer.
 * \param params             Pointer to the structure to be serialised.
 * \param data_length        Number of bytes in the data[] of the struct to be serialised.
 *
 * \return                   \c 1 on success ("okay"), \c 0 on error.
 */
int psasim_serialise_psa_key_production_parameters_t(uint8_t **pos,
                                                     size_t *remaining,
                                                     const psa_key_production_parameters_t *params,
                                                     size_t data_length);

/** Deserialise a psa_key_production_parameters_t.
 *
 * \param pos[in,out]        Pointer to a `uint8_t *` holding current position
 *                           in the serialisation buffer.
 * \param remaining[in,out]  Pointer to a `size_t` holding number of bytes
 *                           remaining in the serialisation buffer.
 * \param params             Pointer to a `psa_key_production_parameters_t *` to
 *                           receive the address of a newly-allocated structure,
 *                           which the caller must `free()`.
 * \param data_length        Pointer to a `size_t` to receive the number of
 *                           bytes in the data[] member of the structure deserialised.
 *
 * \return                   \c 1 on success ("okay"), \c 0 on error.
 */
int psasim_deserialise_psa_key_production_parameters_t(uint8_t **pos, size_t *remaining,
                                                       psa_key_production_parameters_t **params,
                                                       size_t *buffer_length);
EOF
}

sub h_header
{
    return <<'EOF';
/**
 * \file psa_sim_serialise.h
 *
 * \brief Rough-and-ready serialisation and deserialisation for the PSA Crypto simulator
 */

/*
 *  Copyright The Mbed TLS Contributors
 *  SPDX-License-Identifier: Apache-2.0 OR GPL-2.0-or-later
 */

#include <stdint.h>
#include <stddef.h>

#include "psa/crypto.h"
#include "psa/crypto_types.h"
#include "psa/crypto_values.h"

/* Basic idea:
 *
 * All arguments to a function will be serialised into a single buffer to
 * be sent to the server with the PSA crypto function to be called.
 *
 * All returned data (the function's return value and any values returned
 * via `out` parameters) will similarly be serialised into a buffer to be
 * sent back to the client from the server.
 *
 * For each data type foo (e.g. int, size_t, psa_algorithm_t, but also "buffer"
 * where "buffer" is a (uint8_t *, size_t) pair, we have a pair of functions,
 * psasim_serialise_foo() and psasim_deserialise_foo().
 *
 * We also have psasim_serialise_foo_needs() functions, which return a
 * size_t giving the number of bytes that serialising that instance of that
 * type will need. This allows callers to size buffers for serialisation.
 *
 * Each serialised buffer starts with a version byte, bytes that indicate
 * the size of basic C types, and four bytes that indicate the endianness
 * (to avoid incompatibilities if we ever run this over a network - we are
 * not aiming for universality, just for correctness and simplicity).
 *
 * Most types are serialised as a fixed-size (per type) octet string, with
 * no type indication. This is acceptable as (a) this is for the test PSA crypto
 * simulator only, not production, and (b) these functions are called by
 * code that itself is written by script.
 *
 * We also want to keep serialised data reasonably compact as communication
 * between client and server goes in messages of less than 200 bytes each.
 *
 * Many serialisation functions can be created by a script; an exemplar Perl
 * script is included. It is not hooked into the build and so must be run
 * manually, but is expected to be replaced by a Python script in due course.
 * Types that can have their functions created by script include plain old C
 * data types (e.g. int), types typedef'd to those, and even structures that
 * don't contain pointers.
 */

/** Reset all operation slots.
 *
 * Should be called when all clients have disconnected.
 */
void psa_sim_serialize_reset(void);

/** Return how much buffer space is needed by \c psasim_serialise_begin().
 *
 * \return                   The number of bytes needed in the buffer for
 *                           \c psasim_serialise_begin()'s output.
 */
size_t psasim_serialise_begin_needs(void);

/** Begin serialisation into a buffer.
 *
 *                           This must be the first serialisation API called
 *                           on a buffer.
 *
 * \param pos[in,out]        Pointer to a `uint8_t *` holding current position
 *                           in the buffer.
 * \param remaining[in,out]  Pointer to a `size_t` holding number of bytes
 *                           remaining in the buffer.
 *
 * \return                   \c 1 on success ("okay"), \c 0 on error (likely
 *                           no space).
 */
int psasim_serialise_begin(uint8_t **pos, size_t *remaining);

/** Begin deserialisation of a buffer.
 *
 *                           This must be the first deserialisation API called
 *                           on a buffer.
 *
 * \param pos[in,out]        Pointer to a `uint8_t *` holding current position
 *                           in the buffer.
 * \param remaining[in,out]  Pointer to a `size_t` holding number of bytes
 *                           remaining in the buffer.
 *
 * \return                   \c 1 on success ("okay"), \c 0 on error.
 */
int psasim_deserialise_begin(uint8_t **pos, size_t *remaining);
EOF
}

sub define_needs
{
    my ($type) = @_;

    my $type_d = $type;
    $type_d =~ s/ /_/g;

    return <<EOF;

size_t psasim_serialise_${type_d}_needs(
    $type value)
{
    return sizeof(value);
}
EOF
}

sub define_server_needs
{
    my ($type) = @_;

    my $type_d = $type;
    $type_d =~ s/ /_/g;

    return <<EOF;

size_t psasim_server_serialise_${type_d}_needs(
    $type *operation)
{
    (void) operation;

    /* We will actually return a handle */
    return sizeof(psasim_operation_t);
}
EOF
}

sub define_needs_isa
{
    my ($type, $isa) = @_;

    my $type_d = $type;
    $type_d =~ s/ /_/g;

    my $isa_d = $isa;
    $isa_d =~ s/ /_/g;

    return <<EOF;

size_t psasim_serialise_${type_d}_needs(
    $type value)
{
    return psasim_serialise_${isa_d}_needs(value);
}
EOF
}

sub define_serialise
{
    my ($type) = @_;

    my $type_d = $type;
    $type_d =~ s/ /_/g;

    return align_signature(<<EOF);

int psasim_serialise_$type_d(uint8_t **pos,
                             size_t *remaining,
                             $type value)
{
    if (*remaining < sizeof(value)) {
        return 0;
    }

    memcpy(*pos, &value, sizeof(value));
    *pos += sizeof(value);

    return 1;
}
EOF
}

sub define_server_serialise
{
    my ($type) = @_;

    my $t;
    if ($type =~ /^psa_(\w+)_operation_t$/) {
        $t = $1;
    } else {
        die("$0: define_server_serialise: $type: not supported\n");
    }

    my $type_d = $type;
    $type_d =~ s/ /_/g;

    return align_signature(<<EOF);

int psasim_server_serialise_$type_d(uint8_t **pos,
                             size_t *remaining,
                             $type *operation)
{
    psasim_operation_t client_operation;

    if (*remaining < sizeof(client_operation)) {
        return 0;
    }

    ssize_t slot = operation - ${t}_operations;

    client_operation.handle = ${t}_operation_handles[slot];

    memcpy(*pos, &client_operation, sizeof(client_operation));
    *pos += sizeof(client_operation);

    return 1;
}
EOF
}

sub define_serialise_isa
{
    my ($type, $isa) = @_;

    my $type_d = $type;
    $type_d =~ s/ /_/g;

    my $isa_d = $isa;
    $isa_d =~ s/ /_/g;

    return align_signature(<<EOF);

int psasim_serialise_$type_d(uint8_t **pos,
                             size_t *remaining,
                             $type value)
{
    return psasim_serialise_$isa_d(pos, remaining, value);
}
EOF
}

sub define_deserialise
{
    my ($type) = @_;

    my $type_d = $type;
    $type_d =~ s/ /_/g;

    return align_signature(<<EOF);

int psasim_deserialise_$type_d(uint8_t **pos,
                               size_t *remaining,
                               $type *value)
{
    if (*remaining < sizeof(*value)) {
        return 0;
    }

    memcpy(value, *pos, sizeof(*value));

    *pos += sizeof(*value);
    *remaining -= sizeof(*value);

    return 1;
}
EOF
}

sub define_server_deserialise
{
    my ($type) = @_;

    my $t;
    if ($type =~ /^psa_(\w+)_operation_t$/) {
        $t = $1;
    } else {
        die("$0: define_server_serialise: $type: not supported\n");
    }

    my $type_d = $type;
    $type_d =~ s/ /_/g;

    return align_signature(<<EOF);

int psasim_server_deserialise_$type_d(uint8_t **pos,
                               size_t *remaining,
                               $type **operation)
{
    psasim_operation_t client_operation;

    if (*remaining < sizeof(psasim_operation_t)) {
        return 0;
    }

    memcpy(&client_operation, *pos, sizeof(psasim_operation_t));
    *pos += sizeof(psasim_operation_t);
    *remaining -= sizeof(psasim_operation_t);

    ssize_t slot;
    if (client_operation.handle == 0) {         /* We need a new handle */
        slot = allocate_${t}_operation_slot();
    } else {
        slot = find_${t}_slot_by_handle(client_operation.handle);
    }

    if (slot < 0) {
        return 0;
    }

    *operation = &${t}_operations[slot];

    return 1;
}
EOF
}

sub define_deserialise_isa
{
    my ($type, $isa) = @_;

    my $type_d = $type;
    $type_d =~ s/ /_/g;

    my $isa_d = $isa;
    $isa_d =~ s/ /_/g;

    return align_signature(<<EOF);

int psasim_deserialise_$type_d(uint8_t **pos,
                              size_t *remaining,
                              $type *value)
{
    return psasim_deserialise_$isa_d(pos, remaining, value);
}
EOF
}

sub define_buffer_functions
{
    return <<'EOF';

size_t psasim_serialise_buffer_needs(const uint8_t *buffer, size_t buffer_size)
{
    (void) buffer;
    return sizeof(buffer_size) + buffer_size;
}

int psasim_serialise_buffer(uint8_t **pos,
                            size_t *remaining,
                            const uint8_t *buffer,
                            size_t buffer_length)
{
    if (*remaining < sizeof(buffer_length) + buffer_length) {
        return 0;
    }

    memcpy(*pos, &buffer_length, sizeof(buffer_length));
    *pos += sizeof(buffer_length);

    if (buffer_length > 0) {    // To be able to serialise (NULL, 0)
        memcpy(*pos, buffer, buffer_length);
        *pos += buffer_length;
    }

    return 1;
}

int psasim_deserialise_buffer(uint8_t **pos,
                              size_t *remaining,
                              uint8_t **buffer,
                              size_t *buffer_length)
{
    if (*remaining < sizeof(*buffer_length)) {
        return 0;
    }

    memcpy(buffer_length, *pos, sizeof(*buffer_length));

    *pos += sizeof(buffer_length);
    *remaining -= sizeof(buffer_length);

    if (*buffer_length == 0) {          // Deserialise (NULL, 0)
        *buffer = NULL;
        return 1;
    }

    if (*remaining < *buffer_length) {
        return 0;
    }

    uint8_t *data = malloc(*buffer_length);
    if (data == NULL) {
        return 0;
    }

    memcpy(data, *pos, *buffer_length);
    *pos += *buffer_length;
    *remaining -= *buffer_length;

    *buffer = data;

    return 1;
}

/* When the client is deserialising a buffer returned from the server, it needs
 * to use this function to deserialised the  returned buffer. It should use the
 * usual \c psasim_serialise_buffer() function to serialise the outbound
 * buffer. */
int psasim_deserialise_return_buffer(uint8_t **pos,
                                     size_t *remaining,
                                     uint8_t *buffer,
                                     size_t buffer_length)
{
    if (*remaining < sizeof(buffer_length)) {
        return 0;
    }

    size_t length_check;

    memcpy(&length_check, *pos, sizeof(buffer_length));

    *pos += sizeof(buffer_length);
    *remaining -= sizeof(buffer_length);

    if (buffer_length != length_check) {        // Make sure we're sent back the same we sent to the server
        return 0;
    }

    if (length_check == 0) {          // Deserialise (NULL, 0)
        return 1;
    }

    if (*remaining < buffer_length) {
        return 0;
    }

    memcpy(buffer, *pos, buffer_length);
    *pos += buffer_length;
    *remaining -= buffer_length;

    return 1;
}
EOF
}

sub define_psa_key_production_parameters_t_functions
{
    return <<'EOF';

#define SER_TAG_SIZE        4

size_t psasim_serialise_psa_key_production_parameters_t_needs(
    const psa_key_production_parameters_t *params,
    size_t data_length)
{
    /* We will serialise with 4-byte tag = "PKPP" + 4-byte overall length at the beginning,
     * followed by size_t data_length, then the actual data from the structure.
     */
    return SER_TAG_SIZE + sizeof(uint32_t) + sizeof(data_length) + sizeof(*params) + data_length;
}

int psasim_serialise_psa_key_production_parameters_t(uint8_t **pos,
                                                     size_t *remaining,
                                                     const psa_key_production_parameters_t *params,
                                                     size_t data_length)
{
    if (data_length > UINT32_MAX / 2) {       /* arbitrary limit */
        return 0;       /* too big to serialise */
    }

    /* We use 32-bit lengths, which should be enough for any reasonable usage :) */
    /* (the UINT32_MAX / 2 above is an even more conservative check to avoid overflow here) */
    uint32_t len = (uint32_t) (sizeof(data_length) + sizeof(*params) + data_length);
    if (*remaining < SER_TAG_SIZE + sizeof(uint32_t) + len) {
        return 0;
    }

    char tag[SER_TAG_SIZE] = "PKPP";

    memcpy(*pos, tag, sizeof(tag));
    memcpy(*pos + sizeof(tag), &len, sizeof(len));
    *pos += sizeof(tag) + sizeof(len);
    *remaining -= sizeof(tag) + sizeof(len);

    memcpy(*pos, &data_length, sizeof(data_length));
    memcpy(*pos + sizeof(data_length), params, sizeof(*params) + data_length);
    *pos += sizeof(data_length) + sizeof(*params) + data_length;
    *remaining -= sizeof(data_length) + sizeof(*params) + data_length;

    return 1;
}

int psasim_deserialise_psa_key_production_parameters_t(uint8_t **pos,
                                                       size_t *remaining,
                                                       psa_key_production_parameters_t **params,
                                                       size_t *data_length)
{
    if (*remaining < SER_TAG_SIZE + sizeof(uint32_t)) {
        return 0;       /* can't even be an empty serialisation */
    }

    char tag[SER_TAG_SIZE] = "PKPP";    /* expected */
    uint32_t len;

    memcpy(&len, *pos + sizeof(tag), sizeof(len));

    if (memcmp(*pos, tag, sizeof(tag)) != 0) {
        return 0;       /* wrong tag */
    }

    *pos += sizeof(tag) + sizeof(len);
    *remaining -= sizeof(tag) + sizeof(len);

    if (*remaining < sizeof(*data_length)) {
        return 0;       /* missing data_length */
    }
    memcpy(data_length, *pos, sizeof(*data_length));

    if ((size_t) len != (sizeof(data_length) + sizeof(**params) + *data_length)) {
        return 0;       /* wrong length */
    }

    if (*remaining < sizeof(*data_length) + sizeof(**params) + *data_length) {
        return 0;       /* not enough data provided */
    }

    *pos += sizeof(data_length);
    *remaining -= sizeof(data_length);

    psa_key_production_parameters_t *out = malloc(sizeof(**params) + *data_length);
    if (out == NULL) {
        return 0;       /* allocation failure */
    }

    memcpy(out, *pos, sizeof(*out) + *data_length);
    *pos += sizeof(*out) + *data_length;
    *remaining -= sizeof(*out) + *data_length;

    *params = out;

    return 1;
}
EOF
}

sub c_header
{
    return <<'EOF';
/**
 * \file psa_sim_serialise.c
 *
 * \brief Rough-and-ready serialisation and deserialisation for the PSA Crypto simulator
 */

/*
 *  Copyright The Mbed TLS Contributors
 *  SPDX-License-Identifier: Apache-2.0 OR GPL-2.0-or-later
 */

#include "psa_sim_serialise.h"
#include "util.h"
#include <stdlib.h>
#include <string.h>

/* Basic idea:
 *
 * All arguments to a function will be serialised into a single buffer to
 * be sent to the server with the PSA crypto function to be called.
 *
 * All returned data (the function's return value and any values returned
 * via `out` parameters) will similarly be serialised into a buffer to be
 * sent back to the client from the server.
 *
 * For each data type foo (e.g. int, size_t, psa_algorithm_t, but also "buffer"
 * where "buffer" is a (uint8_t *, size_t) pair, we have a pair of functions,
 * psasim_serialise_foo() and psasim_deserialise_foo().
 *
 * We also have psasim_serialise_foo_needs() functions, which return a
 * size_t giving the number of bytes that serialising that instance of that
 * type will need. This allows callers to size buffers for serialisation.
 *
 * Each serialised buffer starts with a version byte, bytes that indicate
 * the size of basic C types, and four bytes that indicate the endianness
 * (to avoid incompatibilities if we ever run this over a network - we are
 * not aiming for universality, just for correctness and simplicity).
 *
 * Most types are serialised as a fixed-size (per type) octet string, with
 * no type indication. This is acceptable as (a) this is for the test PSA crypto
 * simulator only, not production, and (b) these functions are called by
 * code that itself is written by script.
 *
 * We also want to keep serialised data reasonably compact as communication
 * between client and server goes in messages of less than 200 bytes each.
 *
 * Many serialisation functions can be created by a script; an exemplar Perl
 * script is included. It is not hooked into the build and so must be run
 * manually, but is expected to be replaced by a Python script in due course.
 * Types that can have their functions created by script include plain old C
 * data types (e.g. int), types typedef'd to those, and even structures that
 * don't contain pointers.
 */
EOF
}

sub c_define_types_for_operation_types
{
    return <<'EOF';

/* include/psa/crypto_platform.h:typedef uint32_t mbedtls_psa_client_handle_t;
 * but we don't get it on server builds, so redefine it here with a unique type name
 */
typedef uint32_t psasim_client_handle_t;

typedef struct psasim_operation_s {
    psasim_client_handle_t handle;
} psasim_operation_t;

#define MAX_LIVE_HANDLES_PER_CLASS   100        /* this many slots */
EOF
}

sub define_operation_type_data_and_functions
{
    my ($type) = @_;    # e.g. 'hash' rather than 'psa_hash_operation_t'

    my $utype = ucfirst($type);

    return <<EOF;

static psa_${type}_operation_t ${type}_operations[
    MAX_LIVE_HANDLES_PER_CLASS];
static psasim_client_handle_t ${type}_operation_handles[
    MAX_LIVE_HANDLES_PER_CLASS];
static psasim_client_handle_t next_${type}_operation_handle = 1;

/* Get a free slot */
static ssize_t allocate_${type}_operation_slot(void)
{
    psasim_client_handle_t handle = next_${type}_operation_handle++;
    if (next_${type}_operation_handle == 0) {      /* wrapped around */
        FATAL("$utype operation handle wrapped");
    }

    for (ssize_t i = 0; i < MAX_LIVE_HANDLES_PER_CLASS; i++) {
        if (${type}_operation_handles[i] == 0) {
            ${type}_operation_handles[i] = handle;
            return i;
        }
    }

    ERROR("All slots are currently used. Unable to allocate a new one.");

    return -1;  /* all in use */
}

/* Find the slot given the handle */
static ssize_t find_${type}_slot_by_handle(psasim_client_handle_t handle)
{
    for (ssize_t i = 0; i < MAX_LIVE_HANDLES_PER_CLASS; i++) {
        if (${type}_operation_handles[i] == handle) {
            return i;
        }
    }

    ERROR("Unable to find slot by handle %u", handle);

    return -1;  /* not found */
}
EOF
}

sub c_define_begins
{
    return <<'EOF';

size_t psasim_serialise_begin_needs(void)
{
    /* The serialisation buffer will
     * start with a byte of 0 to indicate version 0,
     * then have 1 byte each for length of int, long, void *,
     * then have 4 bytes to indicate endianness. */
    return 4 + sizeof(uint32_t);
}

int psasim_serialise_begin(uint8_t **pos, size_t *remaining)
{
    uint32_t endian = 0x1234;

    if (*remaining < 4 + sizeof(endian)) {
        return 0;
    }

    *(*pos)++ = 0;      /* version */
    *(*pos)++ = (uint8_t) sizeof(int);
    *(*pos)++ = (uint8_t) sizeof(long);
    *(*pos)++ = (uint8_t) sizeof(void *);

    memcpy(*pos, &endian, sizeof(endian));

    *pos += sizeof(endian);

    return 1;
}

int psasim_deserialise_begin(uint8_t **pos, size_t *remaining)
{
    uint8_t version = 255;
    uint8_t int_size = 0;
    uint8_t long_size = 0;
    uint8_t ptr_size = 0;
    uint32_t endian;

    if (*remaining < 4 + sizeof(endian)) {
        return 0;
    }

    memcpy(&version, (*pos)++, sizeof(version));
    if (version != 0) {
        return 0;
    }

    memcpy(&int_size, (*pos)++, sizeof(int_size));
    if (int_size != sizeof(int)) {
        return 0;
    }

    memcpy(&long_size, (*pos)++, sizeof(long_size));
    if (long_size != sizeof(long)) {
        return 0;
    }

    memcpy(&ptr_size, (*pos)++, sizeof(ptr_size));
    if (ptr_size != sizeof(void *)) {
        return 0;
    }

    *remaining -= 4;

    memcpy(&endian, *pos, sizeof(endian));
    if (endian != 0x1234) {
        return 0;
    }

    *pos += sizeof(endian);
    *remaining -= sizeof(endian);

    return 1;
}
EOF
}

# Return the code for psa_sim_serialize_reset()
sub define_server_serialize_reset
{
    my @types = @_;

    my $code = <<EOF;

void psa_sim_serialize_reset(void)
{
EOF

    for my $type (@types) {
        next unless $type =~ /^psa_(\w+_operation)_t$/;

        my $what = $1;  # e.g. "hash_operation"

        $code .= <<EOF;
    memset(${what}_handles, 0,
           sizeof(${what}_handles));
    memset(${what}s, 0,
           sizeof(${what}s));
EOF
    }

    $code .= <<EOF;
}
EOF
}

# Horrible way to align first, second and third lines of function signature to
# appease uncrustify (these are the 2nd-4th lines of code, indices 1, 2 and 3)
#
sub align_signature
{
    my ($code) = @_;

    my @code = split(/\n/, $code);

    # Find where the ( is
    my $idx = index($code[1], "(");
    die("can't find (") if $idx < 0;

    my $indent = " " x ($idx + 1);
    $code[2] =~ s/^\s+/$indent/;
    $code[3] =~ s/^\s+/$indent/;

    return join("\n", @code) . "\n";
}

# Horrible way to align the function declaration to appease uncrustify
#
sub align_declaration
{
    my ($code) = @_;

    my @code = split(/\n/, $code);

    # Find out which lines we need to massage
    my $i;
    for ($i = 0; $i <= $#code; $i++) {
        last if $code[$i] =~ /^int psasim_/;
    }
    die("can't find int psasim_") if $i > $#code;

    # Find where the ( is
    my $idx = index($code[$i], "(");
    die("can't find (") if $idx < 0;

    my $indent = " " x ($idx + 1);
    $code[$i + 1] =~ s/^\s+/$indent/;
    $code[$i + 2] =~ s/^\s+/$indent/;

    return join("\n", @code) . "\n";
}
