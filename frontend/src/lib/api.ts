import { env } from '$env/dynamic/public';

const API_URL = env.PUBLIC_API_URL ?? 'http://localhost:8080';

export interface LoginResult {
	email: string;
}

export class InvalidCredentialsError extends Error {
	constructor() {
		super('Invalid email or password');
	}
}

export class EmailTakenError extends Error {
	constructor() {
		super('That email is already registered');
	}
}

export class NotLoggedInError extends Error {
	constructor() {
		super('Not logged in');
	}
}

export async function login(email: string, password: string): Promise<LoginResult> {
	const response = await fetch(`${API_URL}/api/login`, {
		method: 'POST',
		headers: { 'Content-Type': 'application/json' },
		credentials: 'include',
		body: JSON.stringify({ email, password })
	});

	if (response.status === 401) {
		throw new InvalidCredentialsError();
	}

	if (!response.ok) {
		throw new Error('Something went wrong, try again');
	}

	return response.json();
}

export async function register(email: string, password: string): Promise<LoginResult> {
	const response = await fetch(`${API_URL}/api/register`, {
		method: 'POST',
		headers: { 'Content-Type': 'application/json' },
		credentials: 'include',
		body: JSON.stringify({ email, password })
	});

	if (response.status === 409) {
		throw new EmailTakenError();
	}

	if (!response.ok) {
		throw new Error('Something went wrong, try again');
	}

	return response.json();
}

export async function me(): Promise<LoginResult> {
	const response = await fetch(`${API_URL}/api/me`, {
		method: 'GET',
		credentials: 'include'
	});

	if (response.status === 401) {
		throw new NotLoggedInError();
	}

	if (!response.ok) {
		throw new Error('Something went wrong, try again');
	}

	return response.json();
}

export async function logout(): Promise<void> {
	await fetch(`${API_URL}/api/logout`, {
		method: 'POST',
		credentials: 'include'
	});
}
