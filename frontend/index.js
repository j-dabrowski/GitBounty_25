import { ethers } from "./ethers-6.7.esm.min.js"
import { abi, contractAddress, chainIdMap } from "./constants.js"

let currentAccount = null;

const connectButton = document.getElementById("connectButton")
const enterButton = document.getElementById("enterButton")
const stateButton = document.getElementById("stateButton")
const feeButton = document.getElementById("feeButton")
const winnerButton = document.getElementById("winnerButton")
const timestampButton = document.getElementById("timestampButton")
const toggleThemeButton = document.getElementById("toggle-theme")

connectButton.onclick = connect
enterButton.onclick = enterRaffle
stateButton.onclick = getRaffleState
feeButton.onclick = getEntranceFee
winnerButton.onclick = getRecentWinner
timestampButton.onclick = getLastTimeStamp

toggleThemeButton.addEventListener('click', () => {
  const body = document.body
  body.classList.toggle('dark-mode')
  body.classList.toggle('light-mode')
})

function updateButtons(status) {
  [enterButton, stateButton, feeButton, winnerButton, timestampButton].forEach(btn => {
    btn.disabled = status
  })
}

function pressButton(button, status) {
  button.classList.toggle("pressed", status)
}

updateButtons(true)
document.body.classList.add('light-mode')
connectButton.innerHTML = "Connect Wallet"

async function connect() {
  if (typeof window.ethereum !== "undefined") {
    if (!currentAccount) {
      try {
        await ethereum.request({ method: "eth_requestAccounts" })
        const accounts = await ethereum.request({ method: "eth_accounts" })
        currentAccount = accounts[0]
        const chainId = await ethereum.request({ method: "eth_chainId" })
        const networkName = chainIdMap[chainId] || "Unknown Network"
        const short = currentAccount.slice(0, 7) + "..." + currentAccount.slice(-5)
        pressButton(connectButton, true)
        connectButton.innerHTML = `Connected: ${short} on ${networkName}`
        updateButtons(false)
      } catch (error) {
        console.error(error)
      }
    } else {
      currentAccount = null
      pressButton(connectButton, false)
      connectButton.innerHTML = "Connect Wallet"
      updateButtons(true)
    }
  } else {
    connectButton.innerHTML = "Please install MetaMask"
  }
}

async function enterRaffle() {
  if (typeof window.ethereum !== "undefined") {
    const provider = new ethers.BrowserProvider(window.ethereum)
    const signer = await provider.getSigner()
    const contract = new ethers.Contract(contractAddress, abi, signer)
    try {
      const entranceFee = await contract.getEntranceFee()
      const tx = await contract.enterRaffle({ value: entranceFee })
      await tx.wait(1)
      console.log("Entered Raffle!")
    } catch (err) {
      console.error(err)
    }
  }
}

async function getRaffleState() {
  const provider = new ethers.BrowserProvider(window.ethereum)
  const contract = new ethers.Contract(contractAddress, abi, provider)
  const rawState = await contract.getRaffleState()
  const state = Number(rawState); // convert BigInt → Number
  console.log(`Raffle State: ${state === 0 ? "OPEN" : "CALCULATING"}`)
}

async function getEntranceFee() {
  const provider = new ethers.BrowserProvider(window.ethereum)
  const contract = new ethers.Contract(contractAddress, abi, provider)
  const fee = await contract.getEntranceFee()
  console.log(`Entrance Fee: ${ethers.formatEther(fee)} ETH`)
}

async function getRecentWinner() {
  const provider = new ethers.BrowserProvider(window.ethereum)
  const contract = new ethers.Contract(contractAddress, abi, provider)
  const winner = await contract.getRecentWinner()
  console.log(`Recent Winner: ${winner}`)
}

async function getLastTimeStamp() {
  const provider = new ethers.BrowserProvider(window.ethereum)
  const contract = new ethers.Contract(contractAddress, abi, provider)
  const timestamp = await contract.getLastTimeStamp()
  const date = new Date(Number(timestamp) * 1000)
  console.log(`Last Raffle Time: ${date.toLocaleString()}`)
}
