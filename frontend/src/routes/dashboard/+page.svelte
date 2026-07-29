<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { me, logout, NotLoggedInError } from '$lib/api';

	let email = $state<string | null>(null);

	onMount(async () => {
		try {
			const result = await me();
			email = result.email;
		} catch (error) {
			if (error instanceof NotLoggedInError) {
				await goto('/login');
			}
		}
	});

	async function handleLogout() {
		await logout();
		await goto('/');
	}
</script>

{#if email}
	<h1>Welcome, {email}</h1>
	<button onclick={handleLogout}>Log out</button>
{:else}
	<p>Loading…</p>
{/if}
