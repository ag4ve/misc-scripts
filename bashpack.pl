#!/usr/bin/env perl

use strict;
use warnings;

my @paths = split(':', $ENV{PATH});
push(@paths, ".");

my @files;
push @files, @ARGV;

my $data = {};
my $count = 0;
my $interp;

while (scalar(@files))
{
  my $file = shift(@files);
  # File has been seen
  if (scalar($data) eq 'HASH' and exists($data->{$file}))
  {
    $data->{$file}{count} = $count++;
    next;
  }
  # No file to see
  elsif (! -e $file)
  {
    next;
  }

  open (my $fh, "<", "$file");
  my $buf;
  while (my $line = <$fh>)
  {
    chomp $line;
    # Replace file strings (not variables - which can be dynamic) that are 
    # sourced with the file string
    # TODO spaces are allowed in a file path - are not accepted here
    if ($line =~ /^ *source *([^ \$]+) *$/)
    {
      my $srcstring = $1;
      # Make sure quotes match and strip them
      $srcstring =~ s/^("[^"]+"|'[^']+'|[^'"]+)$/$1/;
      $srcstring =~ s/"'//g;
      if (not length($srcstring))
      {
        warn "Bad source line [$line]\n";
        $buf .= "$line\n";
      }
      else
      {
        my $fullpath;
        # confirm absolute path
        if ($srcstring =~ /\//)
        {
          $fullpath = $srcstring if (-e "$srcstring");
        }
        # search through paths and find the file if it's there
        else
        {
          foreach my $path (@paths)
          {
            if (-e "$path/$srcstring")
            {
              $fullpath = "$path/$srcstring";
              last;
            }
          }
        }
        if (not length($fullpath))
        {
          warn "Source file not found [$line]\n";
          $buf .= "$line\n";
        }
        else
        {
          push @files, $fullpath;
          $buf .= "# Sourced $srcstring\n";
        }
      }
    }
    # Handle shabang
    elsif ($. eq 1 and $line =~ /^#! ?([a-zA-Z0-9\/.,+_ -]+)/)
    {
      if (not defined($interp))
      {
        $interp = $1;
      }
    }
    else
    {
      $buf .= "$line\n";
    }
  }
  $data->{$file}{buf} = $buf;

  $data->{$file}{count} = $count++;
}

print "#! " . $interp . "\n" if (defined($interp));

# Reverse sort file buffers in our hash and print them to stdout
for my $file 
  (
    sort {$data->{$b}{count} <=> $data->{$a}{count}}
    keys %$data
  )
{
  print "# Included $file\n";
  print $data->{$file}{buf};
  print "\n";
}
