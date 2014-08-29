#!/usr/bin/env perl

=head1 LICENSE

Copyright (c) 2014 Illumina, Inc.

This file is part of Illumina's Enhanced Artificial Genome Engine (EAGLE),
covered by the "BSD 2-Clause License" (see accompanying LICENSE file)

=head1 NAME

dbSnpGenotype2vcf.pl

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
use XML::Parser;
use Carp;

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
  . "\t-r, --random-seed=VALUE      - Set random seed (default=0)\n"

  . "\t--help                       - prints usage guide\n"
  . "\t--version                    - prints version information\n"
  . "\n"
  . "\tSTDIN                        - XML data from dbSnp genotype project\n"
  . "\tSTDOUT                       - VCF format\n"
  . "\tSTDERR                       - Stats / Errors\n"
  . "\n"
  . "EXAMPLES:\n"
  . "    wget ftp://ftp.ncbi.nih.gov/snp/organisms/human_9606/genotype/gt_chrX.xml.gz\n"
  . "    zcat gt_chrX.xml.gz | $programName > variants_chrX.vcf\n"
  . "\n";


my $help             = 0;
my $isVersion        = 0;
my %PARAMS           = ();

my $argvStr = join ' ', @ARGV;

$PARAMS{verbose} = 0;
$PARAMS{randomSeed} = 0;


my $result = GetOptions(
    "random-seed|r=s"        => \$PARAMS{randomSeed},

    "version"               => \$isVersion,
    "help"                  => \$help
)
             or pod2usage(2);

# display the version info
if ($isVersion) {
    print $Version_text;
    exit(0);
}

# display the help screen
if ($help) {
    print $usage;
    exit(0);
}

(@ARGV == 0) or die("ERROR: Unrecognized command-line argument(s): @ARGV");


# Program starts here
my $inputFile = "-"; #was $ARGV[0], now always uses STDIN
my $fileSize = -s $inputFile;

my $progressCounter = 0;
my $parseAlleleFreq = 0;
my $alleleFrequenciesFound = 0;
my $parseAlleleByInd = 0;
my %allelesByInd = ();
my $validSnpLocFound = 0;
my $randomValue = 0;

my $rsId;
my $chrom;
my $start;
my $contigAllele;
my $gtype;

my $stats00 = 0;
my $stats01 = 0;
my $stats10 = 0;
my $stats11 = 0;
my $stats12 = 0;

srand($PARAMS{randomSeed});

my $p = new XML::Parser(
    'Handlers' => {
        'Start' => \&handle_start,
        'End'   => \&handle_end,
    }
);

printVcfHeader();
$p->parsefile( $inputFile );


print STDERR "stats00=$stats00\n";
print STDERR "stats01=$stats01\n";
print STDERR "stats10=$stats10\n";
print STDERR "stats11=$stats11\n";
print STDERR "stats12=$stats12\n";

exit 0; # All good




sub printVcfHeader {
  print "##fileformat=VCFv4.1\n";
#  print "##source=$inputFile\n";
  print "##INFO=<ID=DB,Number=0,Type=Flag,Description=\"dbSNP membership, build 135\">\n";
  print "##FORMAT=<ID=GT,Number=1,Type=String,Description=\"Genotype\">\n";
  print "#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\tFORMAT\tSample\n";
}


sub handle_start {
  my ($parser, $element, %attributes) = @_;

  if ($element eq "SnpInfo") {
    $progressCounter++;
    if ($fileSize && $progressCounter % 1000 == 0) {
      my $pos = $parser->current_byte;
      printf STDERR ("%-20s %5.1f%%\n", $element, $pos * 100 / $fileSize);
    }
    $rsId = $attributes{'rsId'};
    $alleleFrequenciesFound = 0;
    $validSnpLocFound = 0;
    # wait for the ByPop entry
    $parseAlleleFreq = 0;
    $parseAlleleByInd = 0;
  }
  elsif ($element eq "SnpLoc") {
    if ($attributes{'genomicAssembly'} eq "37:GRCh37.p5") {
      if (defined $attributes{'chrom'} && defined $attributes{'start'}) {
        $chrom = $attributes{'chrom'};
        $start = $attributes{'start'} + 1; # it is 0-based in dbSNP
        my $locType = $attributes{'locType'};
        my $rsOrientToChrom = $attributes{'rsOrientToChrom'};
        $contigAllele = $attributes{'contigAllele'};
        #print "chrom=$chrom start=$start locType=$locType rsOrientToChrom=$rsOrientToChrom contigAllele=$contigAllele\n";
        $validSnpLocFound = 1;
      }
    }
  }
  elsif ($element eq "ByPop") {
    if ($attributes{'popId'} eq "1409" && !$alleleFrequenciesFound && $validSnpLocFound) {
#print "------------------------------------------ $rsId \n";
      $parseAlleleFreq = 1;
      $parseAlleleByInd = 1;
      %allelesByInd = ();
      $randomValue = rand();
    }
  }
  elsif ($parseAlleleFreq && $element eq "GTypeFreq" && !$alleleFrequenciesFound) {
    $gtype = $attributes{'gtype'};
    my $freq = $attributes{'freq'};
    #print "gtype=$gtype freq=$freq\n";

    if ($randomValue >= 0 && $randomValue < $freq) {
      #print "gtype=$gtype freq=$freq - rsId=$rsId chrom=$chrom start=$start contigAllele=$contigAllele\n";
      processAllele();
      #print "This Genotype got picked\n";
      $parseAlleleFreq = 0;
    }
    $randomValue -= $freq;
    $parseAlleleByInd = 0; # If we have some GTypeFreq info, we don't need to parse GTypeByInd
  }
  elsif ($parseAlleleByInd && $element eq "GTypeByInd") {
    $gtype = $attributes{'gtype'};
    #print "gtype=$gtype\n";
    if (defined $allelesByInd{$gtype}) {
      $allelesByInd{$gtype}++;
    }
    else {
      $allelesByInd{$gtype} = 1;
    }
  }
}


sub handle_end {
  my ($parser, $element) = @_;

  if ($element eq "ByPop") {

    my $nbGtype = keys( %allelesByInd );
    if ($nbGtype > 0) {
      #print "nbGtype=$nbGtype\n";

      my $total = 0;
      for my $k (keys %allelesByInd) {
        if (length($k) == 3 && $k ne 'N/N') {
          #print "val: $k - $allelesByInd{$k}\n";
          $total += $allelesByInd{$k};
        }
        else {
          #print "deleting val: $k - $allelesByInd{$k}\n";
          delete $allelesByInd{$k};
        }
      }
      #print "total=$total\n";

      for my $k (keys %allelesByInd) {
        $gtype = $k;
        my $freq = $allelesByInd{$k} / $total;
        #print "gtype=$gtype freq=$freq randomValue=$randomValue\n";

        if ($randomValue >= 0 && $randomValue < $freq) {
          #print "gtype=$gtype freq=$freq - rsId=$rsId chrom=$chrom start=$start contigAllele=$contigAllele\n";
          processAllele();
          #print "This Genotype got picked\n";
          last;
        }
        $randomValue -= $freq;
      }

      for (keys %allelesByInd) {
        delete $allelesByInd{$_};
      }
      $parseAlleleByInd = 0;
      $alleleFrequenciesFound = 1;
    }
  }
}


sub processAllele() {
  if (length($gtype) == 3) {
    my $allele1 = substr( $gtype, 0, 1 );
    my $allele2 = substr( $gtype, 2, 1 );

    # Deal with unknown allele 0
    if ($allele1 eq "0" or $allele2 eq "0") {
      warn "Non-understood allele 0 for: $chrom\t$start\trs$rsId\t$contigAllele\t$allele1,$allele2\n";
      return;
    }

    # Deal with deletions
    if (length($contigAllele) > 1) {
      $contigAllele = "." . $contigAllele;
      $allele1      = "." . $allele1;
      $allele2      = "." . $allele2;
      $start--;
    }

    # Deal with insertions
    if ($contigAllele eq "-") {
      $contigAllele = ".";
      $allele1      = "." . $allele1;
      $allele2      = "." . $allele2;
      $start--;
    }


    #print "--- $gtype\t$contigAllele\n";

    if ($allele1 eq $allele2) {
      if ($allele1 ne $contigAllele) {
        print "$chrom\t$start\trs$rsId\t$contigAllele\t$allele1\t.\tPASS\tDB\tGT\t1/1\n";
        $stats11++;
      }
      else {
        $stats00++;
      }
    }
    else {
      if ($allele1 ne $contigAllele) {
        if ($allele2 ne $contigAllele) {
          print "$chrom\t$start\trs$rsId\t$contigAllele\t$allele1,$allele2\t.\tPASS\tDB\tGT\t1/2\n";
          $stats12++;
        }
        else {
          print "$chrom\t$start\trs$rsId\t$contigAllele\t$allele1\t.\tPASS\tDB\tGT\t1/0\n";
          $stats10++;
        }
      }
      else {
        if ($allele2 ne $contigAllele) {
          print "$chrom\t$start\trs$rsId\t$contigAllele\t$allele2\t.\tPASS\tDB\tGT\t0/1\n";
          $stats01++;
        }
        else {
          $stats00++;
        }
      }
    }
  }
  else {
    warn "BAD GENOTYPE VALUE for $chrom\t$start\trs$rsId\t$contigAllele\t$gtype (expecting 3 characters)\n";
  }
}
