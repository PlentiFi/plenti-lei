from brownie import PlentiLEIv2, accounts

def main():
    acct = accounts.load("deployer_account")
    name = "PLENTI-LEI"
    symbol = "PLENTILEI"
    gravity_bridge_address = "0x69592e6f9d21989a043646fE8225da2600e5A0f7"
    PlentiLEIv2Contract = PlentiLEIv2.deploy(name, symbol, {"from":acct})
    PlentiLEIv2Contract.setAdjuster(gravity_bridge_address, True, {"from": acct})