#!/usr/bin/env perl

=head1 LICENSE

Copyright (c) 2014 Illumina, Inc.

This file is part of Illumina's Enhanced Artificial Genome Engine (EAGLE),
covered by the "BSD 2-Clause License" (see accompanying LICENSE file)

=head1 NAME

mergeFragments.pl

=head1 DIAGNOSTICS

=head2 Exit status

0: successful completion
1: abnormal completion
2: fatal error

=head2 Errors

All error messages are prefixed with "ERROR: ".

=head2 Warnings

All warning messages generated by EAGLE are prefixed with "WARNING: ".

=head1 CONFIGURATION AND ENVIRONMENT

=back

=head1 BUGS AND LIMITATIONS

There are no known bugs in this module.

All documented features are fully implemented.

Please report problems to Illumina Technical Support (support@illumina.com)

Patches are welcome.

=head1 AUTHOR

Lilian Janin

=cut

use warnings FATAL => 'all';
use strict;
use Cwd qw(abs_path);
use POSIX qw(strftime);
use IO::File;
use Carp;
use File::Spec::Functions qw(rel2abs);

use Pod::Usage;
use Getopt::Long;


my $VERSION = '@EAGLE_VERSION_FULL@';

my $programName = (File::Spec->splitpath(abs_path($0)))[2];
my $programPath = (File::Spec->splitpath(abs_path($0)))[1];
my $Version_text =
    "$programName $VERSION\n"
  . "Copyright (c) 2014 Illumina, Inc.\n";

my $usage =
    "Usage: $programName [options]\n"
  . "\t-i, --input-dir=PATH         - directory containing the input fasta and genome_size.xml files\n"
  . "\t-o, --output-dir=PATH        - output directory\n"
  . "\t-t, --threshold=INTEGER      - files smaller than this number of bases will be combined\n"

  . "\t--help                       - prints usage guide\n"
  . "\t--version                    - prints version information\n"

.<<'EXAMPLES_END';

EXAMPLES:
    (none)

EXAMPLES_END

my $help             = 'nohelp';
my $isVersion        = 0;
my %PARAMS           = ();

my $argvStr = join ' ', @ARGV;

$PARAMS{verbose} = 0;

$PARAMS{inputDir} = "";
$PARAMS{outputDir} = "";
$PARAMS{threshold} = 0;

my $result = GetOptions(
    "input-dir|i=s"         => \$PARAMS{inputDir},
    "output-dir|o=s"        => \$PARAMS{outputDir},
    "threshold|t=i"         => \$PARAMS{threshold},

    "version"               => \$isVersion,
    "help"                  => \$help
);

# display the version info
if ($isVersion) {
    print $Version_text;
    exit(0);
}

# display the help text when no output directory or other required options are given
if ( ( $result == 0 || !$PARAMS{inputDir} || !$PARAMS{outputDir} || !$PARAMS{threshold} ) && 'nohelp' eq $help) {
    die "$usage";
}

die("ERROR: Unrecognized command-line argument(s): @ARGV")  if (0 < @ARGV);

(-e "$PARAMS{inputDir}/genome_size.xml" ) or die "genome_size.xml file required in $PARAMS{inputDir}";
(! -e "$PARAMS{outputDir}" ) or die "$PARAMS{outputDir} already exists";

my $fullInputDir = rel2abs $PARAMS{inputDir};
my $fullOutputDir = rel2abs $PARAMS{outputDir};

# Create output directory
system( "mkdir -p \"${fullOutputDir}\"" );


open GENOMESIZE_XML, "<${fullInputDir}/genome_size.xml" or die "Can't open ${fullInputDir}/genome_size.xml";
open NEW_GENOMESIZE_XML, ">${fullOutputDir}/genome_size.xml" or die "Can't open ${fullOutputDir}/genome_size.xml for writing";

my @contigsToMerge;
my $mergedFileNum = 1;

while (<GENOMESIZE_XML>)
  {
    chomp;
    my $mergePreviousContigs = 1;
    if (/chromosome fileName=\"([^\"]*)\" contigName=\"([^\"]*)\" totalBases=\"([0-9]*)\"/)
      {
        my $fileName   = $1;
        my $contigName = $2;
        my $totalBases = $3;
#        print "xx: $fileName $contigName $totalBases\n";
        if ($totalBases < $PARAMS{threshold})
          {
            push @contigsToMerge, { fileName => "$fileName", contigName => "$contigName", totalBases => "$totalBases" };
            $mergePreviousContigs = 0;
          }
        else
          {
            system( "ln -s \"${fullInputDir}/${fileName}\" \"${fullOutputDir}/${fileName}\"" );
            system( "ln -s \"${fullInputDir}/${fileName}.fai\" \"${fullOutputDir}/${fileName}.fai\"" );
          }
      }

    if ($mergePreviousContigs)
      {
        if (scalar(@contigsToMerge) == 0)
          {
          }
        elsif (scalar(@contigsToMerge) == 1)
          {
            my $fileName   = $contigsToMerge[0]{fileName};
            my $contigName = $contigsToMerge[0]{contigName};
            my $totalBases = $contigsToMerge[0]{totalBases};
            system( "ln -s \"${fullInputDir}/${fileName}\" \"${fullOutputDir}/${fileName}\"" );
            system( "ln -s \"${fullInputDir}/${fileName}.fai\" \"${fullOutputDir}/${fileName}.fai\"" );
            print NEW_GENOMESIZE_XML "    <chromosome fileName=\"$fileName\" contigName=\"$contigName\" totalBases=\"$totalBases\"/>\n";
          }
        else
          {
            my $mergedFileName = $contigsToMerge[0]{fileName} . "_mergedContigs${mergedFileNum}.fa";
            ${mergedFileNum}++;
            for my $href (@contigsToMerge)
              {
                my $fileName   = $href->{fileName};
                my $contigName = $href->{contigName};
                my $totalBases = $href->{totalBases};
                print "Adding ${fileName} to ${mergedFileName}\n";
                system( "cat \"${fullInputDir}/${fileName}\" >> \"${fullOutputDir}/${mergedFileName}\"" );
                print NEW_GENOMESIZE_XML "    <chromosome fileName=\"${mergedFileName}\" contigName=\"$contigName\" totalBases=\"$totalBases\"/>\n";
              }
            print "Indexing ${mergedFileName}\n";
            system( "samtools faidx \"${fullOutputDir}/${mergedFileName}\"" );
          }
        @contigsToMerge = ();
        print NEW_GENOMESIZE_XML "$_\n";
      }
  }
print "Fasta files successfully combined\n";
