from brownie import PlentiLEI, accounts

def main():
    acct = accounts.load("deployer_account")
    name = "PLENTI-LEI"
    symbol = "PLENTILEI"
    PlentiLEI.deploy(name, symbol, {"from":acct})