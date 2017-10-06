import yaml
import shlex
import sys
from subprocess import Popen, PIPE
from colorama import init
from colorama import Fore, Back, Style
init()

# Dictionary merging function
def merge_two_dicts(x, y):
    z = x.copy()
    z.update(y)
    return z

# External command function
def run_command(cmd):
  args = shlex.split(cmd)
  proc = Popen(args, stdout=PIPE, stderr=PIPE)
  out, err = proc.communicate()
  exitcode = proc.returncode
  return exitcode, out, err

global_status = 0

with open('packages.yml') as f:
  dataMap = yaml.safe_load(f)

print ""
print (Fore.CYAN + "\n**************\n* Ruby tests *\n**************")
for package, settings in dataMap['packages'].iteritems():
  package_name = settings['name']
  settings = merge_two_dicts({'test': 'require "%s"' % package_name},settings)
  test = settings['test']
  bin = 'ruby'
  command = bin + " -e '" + test + "'"
  print (Fore.RESET + "Ruby tests for ") + (Fore.CYAN + package_name)  + (Fore.RESET + ":")
  sys.stdout.write("  Can import module without error?.....")
  sys.stdout.flush()
  exitcode, out, err = run_command(command)
  if exitcode == 0:
    print (Fore.GREEN + "Success: Imported.")
  else:
    print (Fore.RED + "Failure:")
    print (Fore.RED + err)
    global_status = exitcode

print (Fore.RESET + "")
sys.exit(global_status)