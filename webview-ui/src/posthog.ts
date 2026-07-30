import posthog from 'posthog-js/dist/module.full.no-external';

const phKey = import.meta.env.VITE_PUBLIC_POSTHOG_KEY;
const phHost = import.meta.env.VITE_PUBLIC_POSTHOG_HOST;

if (phKey && phHost) {
    posthog.init(phKey, {
        api_host: phHost,
        defaults: '2026-05-30',
    });
} else if (import.meta.env.DEV) {
    console.error(
        'VITE_PUBLIC_POSTHOG_KEY variable required by PostHog is missing or un-configured, this causes events to be silently missed. This error stops appearing once VITE_PUBLIC_POSTHOG_KEY is configured'
    );
}

export { posthog };
