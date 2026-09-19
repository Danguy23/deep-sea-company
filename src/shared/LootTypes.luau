--!strict

export type SlotSnapshot = {
	occupied: boolean,
	name: string,
	value: number,
	sizeClass: string,
}

export type Snapshot = {
	slots: {SlotSnapshot},
	selected: number,
	capacity: number,
}

return {}
