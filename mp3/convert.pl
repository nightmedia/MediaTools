#!perl -w
use strict;
use vars qw($OS $flacBinaryPath $defaultEncoding $maxNestingLevel $minFileSize @defaultLameParams $isDebug);
use Cwd;
use Config;
use MP3::Info;
use File::Copy;
unless($OS){unless($OS = $^O){$OS=$Config::Config{'osname'}}}

$flacBinaryPath    = 'c:/apps/flac/flac.exe';
$defaultEncoding   = 'insane';
# Output files smaller than 10K might be the result of an encoding error.
$minFileSize       = 10000;
# How many folders deep to go look for files
$maxNestingLevel   = 10;
@defaultLameParams = (
  '--quiet',
  '--add-id3v2'
);
# Enable this to see debug messages
$isDebug           = 1;

=pod

=head1 Description

This script can be used to convert media files found in a folder structure
to mp3 files, given a certain resolution/preset.

The script will attempt to preserve the ID3/ID3V2 tags if found,
or generate tags based on the folder structure (Artist/Album)

=head1 Usage

You can call this script as described below. 
If there are spaces in the folder name, you need to quote the path.

This will use "lame --preset cbr 160" on all the files in the path:

  convert.pl "c:/Media files/myFolder" preset="cbr 160"

If you are not providing an encoding type, the script will 
use by default "lame --preset fast standard" on all the files in the path:

  convert.pl myFolder


=head2 Parameters

=over

=item preset

This parameter takes the string to be used with the lame --preset option.
See the lame documentation for more information.

Bitrate overview (mostly based on LAME 3.98.2 results)  

 Switch  Preset                  Target Kbit/s  Bitrate range kbit/s  
 -b 320  --preset insane         320            320 CBR
 -V 0    --preset fast extreme   245            220...260
 -V 1                            225            190...250
 -V 2    --preset fast standard  190            170...210
 -V 3                            175            150...195
 -V 4    --preset fast medium    165            140...185
 -V 5                            130            120...150
 -V 6                            115            100...130
 -V 7                            100            80...120
 -V 8                            85             70...105
 -V 9                            65             45...85

=item tags

  tags=id3,path,name

The "tags" parameter specifies how the ID3 tags should be built.
The script will try to use the methods in order. If the ID3 was specified 
and no ID3 was defined, the other methods will be used to define the tags. 

  id3    Use the ID3 tags if defined.
  
  path   Use the last two folders in the path to define the artist and the album name.
         The script will fail if the path is not deep enough to define both.
  
  name   Use the file name to separate the artist, album, and track name.
         The script will fail if the name of a track does not contain all required fields.

When using the "name" parameter, the file name would have to contain
the Artist, Album, and track title, separated by dashes:

  Artist - Album Name - Track Name.mp3

If a track contains the track number in the beginning, it will be used 
to set the track number field.

  01 - Artist - Album Name - Track Name.mp3

=back

=cut

sub makeAbsolutePath {
  my $path = shift;
  # If we are processing files in the current path,
  # we should make it an absolute path for lame.
  # We will also convert windows-style paths to Perl-style paths.
  if ($path eq '.') {
    $path = getcwd();
  }
  elsif ($path !~ /^(\w\:|\/)/) {
    $path = getcwd().'/'.$path;
  }
  $path =~ s/\\/\//g if $path =~ /\\/;
  return $path;
}


sub process {
  $|++;
  my $sourcePath  = shift || Exit("No source path provided");
  my $targetPath  = shift || '';
  my @otherParams = @_;
  if ($targetPath =~ /=/) {
    unshift @otherParams, $targetPath;
    $targetPath = $sourcePath;
  }
  my $inParams   = join ' ', @otherParams;
  
  my (@messages, @errors, %opParams);
  my @outParams = @defaultLameParams;
  my @buildTags = ('id3');
  
  foreach ($sourcePath, $targetPath) {
    $_ = makeAbsolutePath($_);
  }
  Exit("Invalid path provided: $sourcePath") if ! -e $sourcePath || ! -d $sourcePath;
  if (! -e $targetPath) {
    mkdir($targetPath, 0777) || Exit("Could not create path($targetPath):".$!);
  }
  
  if ($inParams =~ /preset=([^\-]+)/) {
    push @outParams, '--preset '.$1;
  }
  else {
    push @messages, qq~You did not provide an encoding standard, using "$defaultEncoding".~;
    push @outParams, '--preset '.$defaultEncoding;
  }
  
  if ($inParams =~ /tags=([^\-]+)/) {
    @buildTags = split ',', lc $1;
    foreach(@buildTags) {
      $_ =~ s/^\s+//;
      $_ =~ s/\s+$//;
      Exit("Invalid tag param: ".$_) if $_ !~ /^(id3|name|path)/o;
    }
    push @messages, "The tags will be built from: ".(join ', then ', @buildTags);
  }
  
  if ($sourcePath ne $targetPath) {
    push @messages, 'The new files will be created in: '.$targetPath;
  }
  
  my $Params = join ' ', @outParams;
  print ''.("=" x 60)."\n".
    (join "\n\n", @messages).
    qq~\n\nThe files in the following path:\n\n\t$sourcePath\n
will be converted using the following call:

\tlame $Params

You have 5 seconds to stop this...\n~;
  sleep 5;
  
  my $errors   = $opParams{-ERRORS}   = [];
  my $messages = $opParams{-MESSAGES} = [];
  
  $opParams{-LAME_PARAMS} = $Params;
  $opParams{-BUILD_TAGS}  = \@buildTags;
  
  WorkDir(\%opParams, $sourcePath, $targetPath);
  
  if (@$messages) {
    print ''.("=" x 60)."\n";
    print "PROCESS RESULTS:\n".(join "\n", @$messages)."\n";
  }
  if (@$errors) {
    print ''.("=" x 60)."\n";
    print "ERRORS found:\n".(join "\n", @$errors)."\n";
  }
  else {
    print "OK\n";
  }
}

sub WorkDir {
  my ($fileName, $message, @errors, @messages);
  my $opParams    = shift;
  my $currentPath = shift;
  my $targetPath  = shift;
  my $level       = shift || 1;
  return if $maxNestingLevel < $level;
  if (! -e $targetPath) {
    mkdir($targetPath, 0777) || Exit("Could not create path($targetPath):".$!);
  }
  my $isProcessInPlace = $currentPath eq $targetPath ? 1 : 0;
  
  my $buildTags  = $opParams->{-BUILD_TAGS};
  my $lameParams = $opParams->{-LAME_PARAMS};
  if (! opendir (DIR, $currentPath)) {
    push @{$opParams->{-ERRORS}}, $currentPath;
    push @{$opParams->{-ERRORS}}, "Can't open $currentPath:. ".$!;
    return;
  }
  my @files = sort grep(!/^\.\.?$/, readdir(DIR));
  closedir (DIR);
  
  print "PATH: $currentPath\n";
  FILE: foreach $fileName(@files) {
    my $sourceFile = "$currentPath/$fileName";
    if (-d $sourceFile) {
      my $newTargetPath = "$targetPath/$fileName";
      if (! -e $newTargetPath) {
        mkdir($newTargetPath, 0777) || Exit("Could not create path($newTargetPath):".$!);
      }
      WorkDir($opParams, $sourceFile, $newTargetPath, $level + 1); 
      next FILE;
    };
    if ($fileName =~ /(.+)\.mp3$/oi) {
      my $targetFile = $isProcessInPlace ? "$currentPath/temp.mp3" : "$targetPath/$fileName";
      unlink($targetFile) if $isProcessInPlace && -e $targetFile;
      print "CONVERT: $fileName\n";
      
      $message = EncodeFile($sourceFile, $targetFile, $lameParams, $buildTags);
      if ($message) {
        push @messages, $fileName;
        push @messages, @$message;
      }
      if (! -e $targetFile) {
        push @errors, $fileName;
        push @errors, "Encode failed, mp3 target file could not be created";
      }
      elsif (-s $targetFile < $minFileSize) {
        push @errors, $fileName;
        push @errors, "Encode failed, output smaller than ".(sprintf "%.2d", $minFileSize / 1000)."KB, keeping original file.";
        unlink($targetFile);
        copy($sourceFile, $targetFile) if ! $isProcessInPlace;
      }
      else {
        if ($isProcessInPlace) {
          unlink($sourceFile);
          rename ($targetFile, $sourceFile) || Exit("could not rename $targetFile to $sourceFile");
        }
      }
    }
    elsif ($fileName =~ /(.+)\.(wav|flac)$/oi) {
      my $fRoot = $1;
      my $targetFileWav;
      if ($fileName =~ /\.flac$/oi) {
        print "CONVERT: $fileName to wav\n";
        $fileName   = "$fRoot.wav";
        $targetFileWav = "$currentPath/$fileName";
        unlink($targetFileWav) if $isProcessInPlace && -e $targetFileWav;
        `$flacBinaryPath -d "$sourceFile" -o "$targetFileWav"`;
        my $oldFile = $sourceFile;
        $sourceFile = "$currentPath/$fileName";
        unlink($oldFile) if $isProcessInPlace && -e $sourceFile;
      }
      my $targetFile = "$targetPath/$fRoot.mp3";
      unlink($targetFile) if $isProcessInPlace && -e $targetFile;
      print "CONVERT: $fileName\n";
      
      $message = EncodeFile($sourceFile, $targetFile, $lameParams, $buildTags);
      unlink($targetFileWav) if $targetFileWav;
      if ($message) {
        push @messages, $fileName;
        push @messages, @$message;
      }
      if (! -e $targetFile) {
        push @errors, $fileName;
        push @errors, "\tEncode failed, see log";
      }
    }
    else {
      print "SKIP: $fileName\n";
    }
  }
  if (@errors) {
    push @{$opParams->{-ERRORS}}, $currentPath;
    push @{$opParams->{-ERRORS}}, map {"  $_"} @errors;
  }
  if (@messages) {
    push @{$opParams->{-MESSAGES}}, $currentPath;
    push @{$opParams->{-MESSAGES}}, map {"  $_"} @messages;
  }
  return;
}

sub Exit {
  my $message = shift;
  print "$message\n";
  exit 1;
}

sub getTagsFromID3 {
  my $Source   = shift;
  my $messages = shift;
  if ($Source !~ /\.mp3$/oi) {
    push @$messages, '=I= Source not an MP3 file, cannot read ID3 tags';
    return {};
  }
  my $tagFromID3 = get_mp3tag($Source) || {};
  if (! keys %$tagFromID3) {
    push @$messages, '=I= MP3 file with no ID3 tags';
  }
  else {
    push @$messages, '=I= MP3 file has ID3 tags';
  }
  return $tagFromID3;
}

sub getTagsFromPath {
  my $Source   = shift;
  my $messages = shift;
  my %tagFromPath;
  if ($Source =~ /([^\/]+)\/([^\/]+)\/(\d+)\s*-\s*([^\/]+)\.w+$/o) {
    push @$messages, '=P= Simple file name, extracting Artist/Album from path.';
    $tagFromPath{ARTIST}   = $1;
    $tagFromPath{ALBUM}    = $2;
    $tagFromPath{TRACKNUM} = $3;
    $tagFromPath{TITLE}    = $4;
  }
  elsif ($Source =~ /(?:Various Artists|V\.A\.?)\/([^\/]+)\/(\d+)\s*(\.|-)\s*([^\/]+)\.w+$/oi) {
    $tagFromPath{ALBUM}    = $1;
    $tagFromPath{TRACKNUM} = $2;
    my $Title = $3;
    $tagFromPath{ARTIST}   = 'Various Artists';
    $tagFromPath{TITLE}    = $Title;
    if ($Title =~ /([^.]+)\s+\.\s+(.+)/o ||
        $Title =~ /([^\-]+)\s+-\s+(.+)/o) {
      $tagFromPath{ARTIST} = $1;
      $tagFromPath{TITLE}  = $2;
      push @$messages, '=P= Extract artist name from file name';
    }
    else {
      push @$messages, '=P= No artist name could be determined from path or file name';
    }
  }
  return \%tagFromPath;
}

sub getTagsFromName {
  my $Source   = shift;
  my $messages = shift;
  return if $Source !~ /([^\/\\]+)\.\w+$/oi;
  my %tagFromName;
  
  my $fileName = $1;
  if ($fileName =~ /^\(([^(]*)\)(.+)/o ||
      $fileName =~ /^\[([^\]]*)\](.+)/) {
    $tagFromName{ALBUM} = $1;
    $fileName           = $2;
    push @$messages, "=N= Album name: $1";
  }
  if ($fileName =~ /(.+)\((\d\d\d\d)\)$/o) {
    $tagFromName{YEAR} = $2;
    $fileName          = $1;
    push @$messages, "=N= Album year: $2";
  }
  
  my @fileName = split /-/, $fileName;
  foreach (@fileName) {
    $_ =~ s/_/ /g;
    $_ =~ s/\s+/ /g;
    $_ =~ s/^\s+//;
    $_ =~ s/\s+$//;
  }
  
  shift @fileName until $fileName[0] ne '' || ! @fileName;
  return \%tagFromName if ! @fileName;
  
  push @$messages, "=N= Using for tagging:\n\t".(join "|", @fileName);
  
  if ($fileName[0] =~ /^\d+$/) {
    $tagFromName{TRACKNUM} = shift @fileName;
  }
  if (2 < @fileName) {
    if (! exists $tagFromName{ALBUM}) {
      $tagFromName{ALBUM}  = shift @fileName;
    }
    $tagFromName{ARTIST} = shift @fileName;
    $tagFromName{TITLE}  = join '-', @fileName;
  }
  elsif (@fileName == 2) {
    $tagFromName{ARTIST} = shift @fileName;
    $tagFromName{TITLE}  = shift @fileName;
  }
  else {
    $tagFromName{TITLE}  = shift @fileName;
  }
  return \%tagFromName;
}


sub EncodeFile {
  my ($x, %tag, $tagSource);
  my $Source     = shift;
  my $Target     = shift;
  my $lameParams = shift;
  my $buildTags  = shift;
  my %DefaultTag = (
    TITLE    => '',
    YEAR     => '',
    ARTIST   => '',
    ALBUM    => '',
    GENRE    => 'Rock',
    TRACKNUM => '',
    COMMENT  => '',
  );
  my (%buildTags, @messages);
  foreach(@$buildTags) {
    $buildTags{$_}++;
  }
  my $tagFromID3  = $buildTags{'id3'}  ? getTagsFromID3($Source, \@messages)  || {} : {};
  my $tagFromPath = $buildTags{'path'} ? getTagsFromPath($Source, \@messages) || {} : {};
  my $tagFromName = $buildTags{'name'} ? getTagsFromName($Source, \@messages) || {} : {};
  
  # These are the params as defined by the MP3::Info
  my @MP3Params = qw(TITLE YEAR ARTIST ALBUM GENRE TRACKNUM COMMENT);
  foreach $x(@MP3Params) {
    foreach $tagSource(@$buildTags) {
      # Once defined, a tag cannot be overriden
      next if exists $tag{$x} && defined $tag{$x} && $tag{$x} ne '';
      
      if ($tagSource eq 'path') {
        $tag{$x} = $tagFromPath->{$x} if exists $tagFromPath->{$x} && defined $tagFromPath->{$x};
      }
      if ($tagSource eq 'id3') {
        $tag{$x} = $tagFromID3->{$x} if exists $tagFromID3->{$x} && defined $tagFromID3->{$x};
      }
      if ($tagSource eq 'name') {
        $tag{$x} = $tagFromName->{$x} if exists $tagFromName->{$x} && defined $tagFromName->{$x};
      }
      $tag{$x} = $DefaultTag{$x} if ! exists $tag{$x} || ! defined $tag{$x} || $tag{$x} eq '';
      $tag{$x} =~ s/\s+$//;
      $tag{$x} =~ s/\s+/ /;
      $tag{$x} =~ s/^\s+//;
      $tag{$x} =~ s/\s+$//;
      $tag{$x} =~ s/^\((.*)\)$/$1/;
      $tag{$x} =~ s/^\[(.*)\]$/$1/;
      $tag{$x} =~ s/^\s+//;
      $tag{$x} =~ s/\s+$//;
      $tag{$x} =~ s/[|\\\/]/~/g; # use "~" instead of one of the following: | / \
      $tag{$x} =~ s/"/'/g; # use ' instead of "
      push @messages, "=== $x($tagSource)=$tag{$x}" if $tag{$x} ne '';
    }
  }
  if ($tag{'TRACKNUM'} =~ /(\d+)\D/) {
    $tag{'TRACKNUM'} = $1;
  }
  $lameParams .= qq~ --tt "$tag{'TITLE'}"~    if $tag{'TITLE'}    ne '';
  $lameParams .= qq~ --ty "$tag{'YEAR'}"~     if $tag{'YEAR'}     ne '';
  $lameParams .= qq~ --ta "$tag{'ARTIST'}"~   if $tag{'ARTIST'}   ne '';
  $lameParams .= qq~ --tl "$tag{'ALBUM'}"~    if $tag{'ALBUM'}    ne '';
  $lameParams .= qq~ --tg "$tag{'GENRE'}"~    if $tag{'GENRE'}    ne '';
  $lameParams .= qq~ --tn "$tag{'TRACKNUM'}"~ if $tag{'TRACKNUM'} ne '';
  $lameParams .= qq~ --tc "$tag{'COMMENT'}"~  if $tag{'COMMENT'}  ne '';
  
  
  if ($OS =~ /win/oi) {
    $Source =~ s/\//\\/g;
    $Target =~ s/\//\\/g;
  }
  my $sourceSize = -s $Source;
  my $cmd = qq~lame $lameParams "$Source" "$Target"~;
  push @messages, "=== RUN: $cmd";
  `$cmd`;
  my $targetSize = -e $Target ? -s $Target : 0;
  
  push @messages, $sourceSize && $targetSize ? 
    "Size changed from ".(sprintf '%.2d', $sourceSize / 1000)."K to ".(sprintf '%.2d', $targetSize / 1000)."K." :
    'ERROR:Could not convert';
  push @messages, ("=" x 40);
  
  @messages = () if ! $isDebug;
  
  return \@messages;
}

process(@ARGV);
